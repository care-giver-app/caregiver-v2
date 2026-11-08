package domain

import (
	"fmt"
	"testing"
	"time"
)

func TestTemplates(t *testing.T) {
	tps := Templates()
	var ids []string
	for _, tp := range tps {
		ids = append(ids, tp.TemplateID)
	}
	want := "[mood shower urination bowel_movement medication walk weight doctor_appointment]"
	if fmt.Sprint(ids) != want {
		t.Fatalf("catalogue order = %v, want %s", ids, want)
	}
	for _, tp := range tps {
		if _, err := ValidateTrackerName(tp.Name); err != nil {
			t.Errorf("%s: %v", tp.TemplateID, err)
		}
		if err := ValidateColor(tp.Color); err != nil {
			t.Errorf("%s: %v", tp.TemplateID, err)
		}
		if err := ValidateGapHours(tp.GapHours); err != nil {
			t.Errorf("%s: %v", tp.TemplateID, err)
		}
		if tp.Icon == "" {
			t.Errorf("%s: no icon", tp.TemplateID)
		}
		ws := make([]FieldWrite, 0, len(tp.Fields))
		for _, f := range tp.Fields {
			w := FieldWrite{Label: f.Label, Type: f.Type, Unit: f.Unit, Required: f.Required, Multiple: f.Multiple}
			if f.Range != nil {
				w.Range = &Range{Low: f.Range.Low, High: f.Range.High}
			}
			for _, o := range f.Options {
				w.Options = append(w.Options, OptionWrite{Label: o.Label})
			}
			ws = append(ws, w)
		}
		fields, err := NewFields(ws, time.Now())
		if err != nil {
			t.Errorf("%s: %v", tp.TemplateID, err)
		}
		if len(fields) != len(tp.Fields) {
			t.Errorf("%s: %d fields, want %d", tp.TemplateID, len(fields), len(tp.Fields))
		}
	}

	shower, weight := tps[1], tps[6]
	if len(shower.Fields) != 0 || shower.GapHours == nil || *shower.GapHours != 72 {
		t.Errorf("shower: %+v", shower)
	}
	if r := weight.Fields[0].Range; r == nil || *r.Low != 80 || *r.High != 400 || weight.Fields[0].Unit != "lb" {
		t.Errorf("weight: %+v", weight.Fields[0])
	}
}
