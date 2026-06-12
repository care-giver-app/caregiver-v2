package domain

import "testing"

func TestTemplates_loadsAndIsValid(t *testing.T) {
	tps := Templates()
	if len(tps) == 0 {
		t.Fatal("expected a non-empty template catalog")
	}
	seen := map[string]bool{}
	for _, tp := range tps {
		if tp.TemplateID == "" || tp.Name == "" {
			t.Fatalf("template missing id/name: %+v", tp)
		}
		if seen[tp.TemplateID] {
			t.Fatalf("duplicate template_id %q", tp.TemplateID)
		}
		seen[tp.TemplateID] = true
		if !tp.Kind.Valid() {
			t.Fatalf("template %q has invalid kind %q", tp.TemplateID, tp.Kind)
		}
		for _, f := range tp.Fields {
			if f.Key == "" || !f.Type.Valid() {
				t.Fatalf("template %q has invalid field %+v", tp.TemplateID, f)
			}
			if f.Type == FieldEnum && len(f.Options) == 0 {
				t.Fatalf("template %q enum field %q has no options", tp.TemplateID, f.Key)
			}
		}
	}
}
