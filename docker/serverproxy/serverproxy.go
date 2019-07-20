package main

import (
	"crypto/sha256"
	"io"
	"log"
	"math/rand"
	"net"
	"net/http"
	"net/http/fcgi"
	"net/url"
	"os"
	"os/exec"
	"sync"
	"time"
)

const sockAddr = "/tmp/fcgisock"
const maxProcsPerScript = 5
const maxCreationIntervalMs = 100

type fileHash struct {
	hash string
	time time.Time
}

type pyProcHandles struct {
	hash         string
	procs        []*os.Process
	ports        []int
	lastAccessed time.Time
}

// string (path) -> fileHash
var fileHashes sync.Map

// string (hash) -> pyProc
var pyProcs sync.Map

type myHandler struct{}

func (myHandler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	path := req.URL.Path
	rq := req.URL.RawQuery
	q := url.ParseQuery(rq)

	info, err := os.Stat(path)
	if err != nil {
		panic("TODO: internal server error or not found")
	}

	modtime := info.ModTime()

	fhi, fhOk := fileHashes.Load(path)
	if !fhOk {
		f, err := os.Open(path)
		if err != nil {
			panic("TODO: not found")
		}
		defer f.Close()
		h := sha256.New()
		if _, err := io.Copy(h, f); err != nil {
			panic("TODO: internal server error")
		}
		fhi := h.Sum()
		fileHashes.Store(path, fhi)
	}

	fh := fhi.(fileHash)
	procsi, procsOk := pyProcs.Load(fh.hash)
	if !procsOk {

	} else {
		procs := procsi.(pyProcHandles)
		nw := time.Now()
		diff := nw.Sub(procs.lastAccessed)
		if len(procs.procs) < maxProcsPerScript && diff < maxCreationIntervalMs*1000000 {
			cmd := exec.Command(path)
			cmd.Env = os.Environ()
			for k, v := range q {
				s := k + "=" + v
				cmd.Env = append(cmd.Env, s)
			}
			if err := Cmd.Run(); err != nil {
				panic("TODO: internal server error [2]")
			}
			procs.procs = append(procs.procs, cmd.Process)
		} else {
			r := rand.Intn(len(procs.procs))
			if
		}
	}
}

func main() {
	listener, err := net.Listen("unix", sockAddr)
	if err != nil {
		log.Fatal(err)
	}

	fcgi.Serve(listener, myHandler{})
}
