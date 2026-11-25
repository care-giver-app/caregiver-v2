package v1

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

type testPool struct {
	key     *rsa.PrivateKey
	kid     string
	fetches atomic.Int32
	srv     *httptest.Server
}

func newTestPool(t *testing.T) *testPool {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	p := &testPool{key: key, kid: "k1"}
	p.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p.fetches.Add(1)
		enc := base64.RawURLEncoding
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kid": p.kid, "kty": "RSA", "alg": "RS256", "use": "sig",
			"n": enc.EncodeToString(key.N.Bytes()),
			"e": enc.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
		}}})
	}))
	t.Cleanup(p.srv.Close)
	return p
}

func (p *testPool) verifier(now time.Time) *TokenVerifier {
	v := NewCognitoVerifier("us-east-2", "us-east-2_pool", "client")
	v.jwksURL = p.srv.URL
	v.now = func() time.Time { return now }
	return v
}

func (p *testPool) sign(t *testing.T, header, body map[string]any) string {
	t.Helper()
	enc := base64.RawURLEncoding
	h, _ := json.Marshal(header)
	b, _ := json.Marshal(body)
	signing := enc.EncodeToString(h) + "." + enc.EncodeToString(b)
	digest := sha256.Sum256([]byte(signing))
	sig, err := rsa.SignPKCS1v15(rand.Reader, p.key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return signing + "." + enc.EncodeToString(sig)
}

func TestTokenVerifier(t *testing.T) {
	now := time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)
	pool := newTestPool(t)
	v := pool.verifier(now)
	header := map[string]any{"alg": "RS256", "kid": "k1"}
	good := func() map[string]any {
		return map[string]any{
			"sub": "sub-1", "iss": "https://cognito-idp.us-east-2.amazonaws.com/us-east-2_pool",
			"aud": "client", "token_use": "id", "exp": now.Add(time.Hour).Unix(),
			"email": "sam@x.com", "email_verified": true, "name": "Sam Lee",
		}
	}
	bearer := func(tok string) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/v1/feedback", nil)
		r.Header.Set("Authorization", "Bearer "+tok)
		return r
	}

	c, ok := v.claimsFromBearer(bearer(pool.sign(t, header, good())))
	if !ok || c != (claims{Sub: "sub-1", Email: "sam@x.com", Name: "Sam Lee", EmailVerified: "true"}) {
		t.Fatalf("good token: %+v %v", c, ok)
	}

	for name, change := range map[string]func(h, b map[string]any){
		"expired":       func(_, b map[string]any) { b["exp"] = now.Unix() },
		"other pool":    func(_, b map[string]any) { b["iss"] = "https://cognito-idp.us-east-2.amazonaws.com/other" },
		"other client":  func(_, b map[string]any) { b["aud"] = "someone-else" },
		"access token":  func(_, b map[string]any) { b["token_use"] = "access" },
		"no sub":        func(_, b map[string]any) { delete(b, "sub") },
		"none alg":      func(h, _ map[string]any) { h["alg"] = "none" },
		"HS256":         func(h, _ map[string]any) { h["alg"] = "HS256" },
		"unknown kid":   func(h, _ map[string]any) { h["kid"] = "k-unknown" },
		"no kid at all": func(h, _ map[string]any) { delete(h, "kid") },
	} {
		h, b := map[string]any{"alg": "RS256", "kid": "k1"}, good()
		change(h, b)
		if _, ok := v.claimsFromBearer(bearer(pool.sign(t, h, b))); ok {
			t.Errorf("%s: verified", name)
		}
	}

	// A token whose body was changed after signing.
	tok := pool.sign(t, header, good())
	forged := good()
	forged["sub"] = "sub-2"
	fb, _ := json.Marshal(forged)
	parts := splitToken(tok)
	if _, ok := v.claimsFromBearer(bearer(parts[0] + "." + base64.RawURLEncoding.EncodeToString(fb) + "." + parts[2])); ok {
		t.Error("tampered body verified")
	}
	for _, raw := range []string{"", "a.b", "a.b.c", "Basic xyz"} {
		r := httptest.NewRequest(http.MethodPost, "/", nil)
		r.Header.Set("Authorization", raw)
		if _, ok := v.claimsFromBearer(r); ok {
			t.Errorf("%q verified", raw)
		}
	}

	// Unknown key ids do not fetch the key set more than every few minutes.
	if n := pool.fetches.Load(); n != 1 {
		t.Fatalf("fetches = %d, want 1", n)
	}
}

func TestTokenVerifier_picksUpARotatedKey(t *testing.T) {
	now := time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)
	pool := newTestPool(t)
	v := pool.verifier(now)
	body := map[string]any{
		"sub": "s", "iss": "https://cognito-idp.us-east-2.amazonaws.com/us-east-2_pool",
		"aud": "client", "token_use": "id", "exp": now.Add(2 * time.Hour).Unix(),
	}
	if _, ok := v.claimsFromBearer(withBearer(pool.sign(t, map[string]any{"alg": "RS256", "kid": "k1"}, body))); !ok {
		t.Fatal("first key")
	}
	pool.kid = "k2"
	rotated := pool.sign(t, map[string]any{"alg": "RS256", "kid": "k2"}, body)
	if _, ok := v.claimsFromBearer(withBearer(rotated)); ok {
		t.Fatal("a new key id right after a fetch waits")
	}
	v.now = func() time.Time { return now.Add(jwksRefetchAfter) }
	if _, ok := v.claimsFromBearer(withBearer(rotated)); !ok {
		t.Fatal("the rotated key is fetched once the wait is over")
	}
}

func withBearer(tok string) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/", nil)
	r.Header.Set("Authorization", "Bearer "+tok)
	return r
}

func splitToken(tok string) [3]string {
	var out [3]string
	i := 0
	start := 0
	for j := 0; j < len(tok); j++ {
		if tok[j] == '.' {
			out[i] = tok[start:j]
			i++
			start = j + 1
		}
	}
	out[2] = tok[start:]
	return out
}
