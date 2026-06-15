// Funke-Relay: winziger HTTPS-Endpoint, der Notizen als .md-Dateien in einen
// Vault-Ordner schreibt. obsidian-headless (separater Daemon) synct den Ordner
// zu Obsidian Sync und verteilt die Datei an alle Geräte.
//
// Single static binary, keine Dependencies (nur Go-Standardbibliothek).
//
// Env:
//   FUNKE_VAULT  Pfad zum Vault-Ordner (z. B. /srv/obsidian/vault)  [Pflicht]
//   FUNKE_TOKEN  Bearer-Token, muss zum Token in der App passen      [Pflicht]
//   FUNKE_ADDR   Listen-Adresse (Default ":8787")
//
// TLS terminiert vorgelagert (empfohlen: `tailscale serve`, siehe README).
package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type noteRequest struct {
	Folder    string `json:"folder"`
	Filename  string `json:"filename"`
	Content   string `json:"content"`
	CreatedAt string `json:"createdAt"`
}

func main() {
	vault := mustEnv("FUNKE_VAULT")
	token := mustEnv("FUNKE_TOKEN")
	addr := envOr("FUNKE_ADDR", ":8787")

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r, token) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/notes", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if !authorized(r, token) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		var req noteRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
			http.Error(w, `{"error":"bad json"}`, http.StatusBadRequest)
			return
		}

		rel, err := safeRelPath(req.Folder, req.Filename)
		if err != nil {
			http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
			return
		}

		full := filepath.Join(vault, rel)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			http.Error(w, `{"error":"mkdir failed"}`, http.StatusInternalServerError)
			return
		}
		if err := atomicWrite(full, []byte(req.Content)); err != nil {
			http.Error(w, `{"error":"write failed"}`, http.StatusInternalServerError)
			return
		}

		log.Printf("wrote note: %s (%d bytes)", rel, len(req.Content))
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"ok":true}`))
	})

	log.Printf("funke-relay listening on %s, vault=%s", addr, vault)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func authorized(r *http.Request, token string) bool {
	got := r.Header.Get("Authorization")
	want := "Bearer " + token
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// safeRelPath baut einen vault-relativen Pfad und verhindert Path-Traversal.
// filename ist client-seitig bereits sanitisiert (NoteFileName); hier zusätzlich
// hart abgesichert: keine Slashes im Dateinamen, kein "..", kein absoluter Pfad.
func safeRelPath(folder, filename string) (string, error) {
	filename = strings.TrimSpace(filename)
	if filename == "" {
		return "", errors.New("empty filename")
	}
	if strings.ContainsAny(filename, `/\`) {
		return "", errors.New("filename must not contain slashes")
	}

	folder = strings.Trim(strings.TrimSpace(folder), `/\`)
	if strings.Contains(folder, "..") {
		return "", errors.New("invalid folder")
	}

	rel := filepath.Clean(filepath.Join(folder, filename+".md"))
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return "", errors.New("invalid path")
	}
	return rel, nil
}

func atomicWrite(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("missing required env %s", key)
	}
	return v
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
