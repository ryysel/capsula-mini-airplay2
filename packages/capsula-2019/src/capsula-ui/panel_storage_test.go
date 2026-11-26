package main

import (
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestSaveRetriesAfterStorageError(t *testing.T) {
	dir := t.TempDir()
	blocker := filepath.Join(dir, "blocked")
	if err := os.WriteFile(blocker, []byte("file"), 0600); err != nil {
		t.Fatal(err)
	}
	old := panelPath
	defer func() { panelPath = old }()
	panelPath = filepath.Join(blocker, "panel.json")
	panelMarkDirty()
	w := httptest.NewRecorder()
	panelHandleSave(w, httptest.NewRequest("POST", "/api/save", nil))
	if w.Code != 500 {
		t.Fatalf("storage error returned %d", w.Code)
	}
	panelPath = filepath.Join(dir, "panel.json")
	if err := panelFlush(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(panelPath); err != nil {
		t.Fatal(err)
	}
}
