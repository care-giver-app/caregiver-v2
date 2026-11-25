package v1

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

// TokenVerifier checks a Cognito ID token in-process, for the one route that
// API Gateway's JWT authorizer cannot guard: POST /v1/feedback, where a token
// is optional and the authorizer would refuse a request without one. It does
// what the authorizer does — an RS256 signature by one of the pool's keys,
// the pool as issuer, the app client as audience, not expired — and also
// requires an ID token, which is what every client sends.
type TokenVerifier struct {
	issuer   string
	clientID string
	jwksURL  string
	http     *http.Client
	now      func() time.Time

	mu        sync.Mutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

// jwksRefetchAfter is how soon an unknown key id may fetch the key set again:
// often enough to pick up a rotated key, rarely enough that tokens with made
// up key ids cannot make every request a fetch.
const jwksRefetchAfter = 5 * time.Minute

// NewCognitoVerifier verifies ID tokens from the pool for the app client.
func NewCognitoVerifier(region, poolID, clientID string) *TokenVerifier {
	issuer := fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s", region, poolID)
	return &TokenVerifier{
		issuer: issuer, clientID: clientID, jwksURL: issuer + "/.well-known/jwks.json",
		http: &http.Client{Timeout: 3 * time.Second}, now: time.Now,
	}
}

var errBadToken = errors.New("invalid token")

// claimsFromBearer is an Authenticator extractor: the verified claims of the
// request's bearer token, or false when there is none or it does not verify.
func (v *TokenVerifier) claimsFromBearer(r *http.Request) (claims, bool) {
	raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || raw == "" {
		return claims{}, false
	}
	cl, err := v.verify(r.Context(), strings.TrimSpace(raw))
	if err != nil {
		return claims{}, false
	}
	return cl, true
}

type tokenClaims struct {
	Sub           string `json:"sub"`
	Iss           string `json:"iss"`
	Aud           string `json:"aud"`
	TokenUse      string `json:"token_use"`
	Exp           int64  `json:"exp"`
	Email         string `json:"email"`
	EmailVerified any    `json:"email_verified"`
	Name          string `json:"name"`
	GivenName     string `json:"given_name"`
	FamilyName    string `json:"family_name"`
}

func (v *TokenVerifier) verify(ctx context.Context, raw string) (claims, error) {
	parts := strings.Split(raw, ".")
	if len(parts) != 3 {
		return claims{}, errBadToken
	}
	var header struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}
	if err := decodeSegment(parts[0], &header); err != nil || header.Alg != "RS256" || header.Kid == "" {
		return claims{}, errBadToken
	}
	key, err := v.key(ctx, header.Kid)
	if err != nil {
		return claims{}, err
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return claims{}, errBadToken
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig) != nil {
		return claims{}, errBadToken
	}
	var tc tokenClaims
	if err := decodeSegment(parts[1], &tc); err != nil {
		return claims{}, errBadToken
	}
	if tc.Iss != v.issuer || tc.Aud != v.clientID || tc.TokenUse != "id" || tc.Sub == "" ||
		v.now().Unix() >= tc.Exp {
		return claims{}, errBadToken
	}
	name := tc.Name
	if name == "" {
		name = strings.TrimSpace(tc.GivenName + " " + tc.FamilyName)
	}
	verified := ""
	switch ev := tc.EmailVerified.(type) {
	case bool:
		verified = fmt.Sprint(ev)
	case string:
		verified = ev
	}
	return claims{Sub: tc.Sub, Email: tc.Email, Name: name, EmailVerified: verified}, nil
}

func decodeSegment(seg string, v any) error {
	b, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// key returns the pool's public key with the id, fetching the key set the
// first time and again, at most every jwksRefetchAfter, for an id not in it.
func (v *TokenVerifier) key(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if k, ok := v.keys[kid]; ok {
		return k, nil
	}
	if v.keys != nil && v.now().Sub(v.fetchedAt) < jwksRefetchAfter {
		return nil, errBadToken
	}
	keys, err := v.fetch(ctx)
	if err != nil {
		return nil, err
	}
	v.keys, v.fetchedAt = keys, v.now()
	if k, ok := keys[kid]; ok {
		return k, nil
	}
	return nil, errBadToken
}

func (v *TokenVerifier) fetch(ctx context.Context) (map[string]*rsa.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.jwksURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := v.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching the pool's keys: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetching the pool's keys: %s", resp.Status)
	}
	var set struct {
		Keys []struct {
			Kid string `json:"kid"`
			Kty string `json:"kty"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, fmt.Errorf("reading the pool's keys: %w", err)
	}
	keys := map[string]*rsa.PublicKey{}
	for _, k := range set.Keys {
		if k.Kty != "RSA" {
			continue
		}
		n, nerr := base64.RawURLEncoding.DecodeString(k.N)
		e, eerr := base64.RawURLEncoding.DecodeString(k.E)
		if nerr != nil || eerr != nil || len(e) == 0 || len(e) > 4 {
			continue
		}
		keys[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}
	}
	return keys, nil
}
