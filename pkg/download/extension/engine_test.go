package extension

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/GopeedLab/gopeed/internal/test"
	"github.com/GopeedLab/gopeed/pkg/download/extension/inject/file"
	"github.com/dop251/goja"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestPolyfill(t *testing.T) {
	doTestPolyfill(t, "XMLHttpRequest")
	doTestPolyfill(t, "Blob")
	doTestPolyfill(t, "FormData")
	doTestPolyfill(t, "fetch")
}

func TestFetch(t *testing.T) {
	server := startServer()
	defer server.Close()
	engine := NewEngine()
	if _, err := engine.RunString(fmt.Sprintf("var host = 'http://%s';", server.Addr().String())); err != nil {
		t.Fatal(err)
	}
	_, err := engine.RunString(`
async function testGet(){
	const resp = await fetch(host+'/get');
	return resp.status;
}

async function testText(){
	const resp = await fetch(host+'/text',{
		method: 'POST',
		body: 'test'
	});
	return await resp.text();
}

async function testOctetStream(file){
	const resp = await fetch(host+'/octetStream',{
		method: 'POST',
		body: file
	});
	return await resp.text();
}

async function testFormData(file){
	const formData = new FormData();
	formData.append('name', 'test');
	formData.append('f', file);
	const resp = await fetch(host+'/formData',{
		method: 'POST',
		body: formData
	});
	return await resp.json();
}

function testProgress(){
	return new Promise((resolve, reject) => {
		const xhr = new XMLHttpRequest();
		xhr.open('GET', host+'/get');
		const xhrUploadPromise = new Promise((resolve, reject) => {
			xhr.upload.onprogress = function(e){
				if(e.loaded === e.total){
					resolve();
				}
			}
		});
		const xhrPromise = new Promise((resolve, reject) => {
			xhr.onprogress = function(e){
				if(e.loaded === e.total){
					resolve();
				}
			}
		});
		Promise.all([xhrUploadPromise, xhrPromise]).then(() => {
			resolve();
		});
		xhr.send();
		setTimeout(() => {
			reject('timeout');
		}, 1000);
	});
}

function testAbort(){
	return new Promise((resolve, reject) => {
		const xhr = new XMLHttpRequest();
		xhr.open('GET', host+'/timeout?duration=500');
		xhr.onabort = function() {
			resolve();
		};
		xhr.send();
		setTimeout(() => {
			xhr.abort();
		}, 200);
		setTimeout(() => {
			reject('timeout');
		}, 1000);
	});
}

function testTimeout(){
	return new Promise((resolve, reject) => {
		const xhr = new XMLHttpRequest();
		const t = 500;
		xhr.open('GET', host+'/timeout?duration='+t);
		xhr.timeout = t - 200;
		xhr.onload = function() {
			resolve();
		};
		xhr.ontimeout = function() {
			reject('timeout');
		};
		xhr.send();
	});
}
`)
	if err != nil {
		t.Fatal(err)
	}

	result, err := callTestFun(engine, "testGet")
	if err != nil {
		t.Fatal(err)
	}
	if result != int64(200) {
		t.Fatalf("testGet failed, want %d, got %d", 200, result)
	}

	result, err = callTestFun(engine, "testText")
	if err != nil {
		t.Fatal(err)
	}
	if result != "test" {
		t.Fatalf("testText failed, want %s, got %s", "test", result)
	}

	func() {
		jsFile, _, md5 := buildFile(t, engine.Runtime)
		result, err = callTestFun(engine, "testOctetStream", jsFile)
		if err != nil {
			t.Fatal(err)
		}
		if result != md5 {
			t.Fatalf("testOctetStream failed, want %s, got %s", md5, result)
		}
	}()

	func() {
		jsFile, goFile, md5 := buildFile(t, engine.Runtime)
		result, err = callTestFun(engine, "testFormData", jsFile)
		if err != nil {
			t.Fatal(err)
		}
		want := map[string]any{
			"name": "test",
			"f": map[string]string{
				"filename": goFile.Name,
				"md5":      md5,
			},
		}
		if !test.JsonEqual(result, want) {
			t.Fatalf("testFormData failed, want %v, got %v", want, result)
		}
	}()

	_, err = callTestFun(engine, "testProgress")
	if err != nil {
		t.Fatal("progress test failed")
	}

	_, err = callTestFun(engine, "testAbort")
	if err != nil {
		t.Fatal("abort test failed")
	}

	_, err = callTestFun(engine, "testTimeout")
	if err == nil || err.Error() != "timeout" {
		t.Fatalf("timeout test failed, want %s, got %s", "timeout", err)
	}
}

func doTestPolyfill(t *testing.T, module string) {
	value, err := Run(fmt.Sprintf(`
!!globalThis['%s']
`, module))
	if err != nil {
		t.Fatal(err)
	}
	if !value.ToBoolean() {
		t.Fatalf("module %s not polyfilled", module)
	}
}

func startServer() net.Listener {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	server := &http.Server{}
	mux := http.NewServeMux()
	mux.HandleFunc("/get", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/text", func(w http.ResponseWriter, r *http.Request) {
		buf, _ := io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		w.Write(buf)
	})
	mux.HandleFunc("/octetStream", func(w http.ResponseWriter, r *http.Request) {
		md5 := calcMd5(r.Body)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(md5))
	})
	mux.HandleFunc("/formData", func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseMultipartForm(1024 * 1024 * 30)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			w.Write([]byte(err.Error()))
			return
		}
		result := make(map[string]any)
		for k, v := range r.MultipartForm.Value {
			result[k] = v[0]
		}
		for k, v := range r.MultipartForm.File {
			f, _ := v[0].Open()
			result[k] = map[string]string{
				"filename": v[0].Filename,
				"md5":      calcMd5(f),
			}
		}
		w.WriteHeader(http.StatusOK)
		buf, _ := json.Marshal(result)
		w.Write(buf)
	})
	mux.HandleFunc("/timeout", func(w http.ResponseWriter, r *http.Request) {
		duration := r.URL.Query().Get("duration")
		t, _ := strconv.Atoi(duration)
		time.Sleep(time.Duration(t) * time.Millisecond)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	server.Handler = mux
	go server.Serve(listener)
	return listener
}

func buildFile(t *testing.T, runtime *goja.Runtime) (goja.Value, *file.File, string) {
	jsFile, err := file.NewJsFile(runtime)
	if err != nil {
		t.Fatal(err)
	}
	f := jsFile.Export().(*file.File)
	data := "test"
	f.Reader = strings.NewReader(data)
	f.Name = "test.txt"
	f.Size = int64(len(data))
	return jsFile, f, calcMd5(strings.NewReader(data))
}

func callTestFun(engine *Engine, fun string, args ...any) (any, error) {
	test, ok := goja.AssertFunction(engine.Runtime.Get(fun))
	if !ok {
		return nil, errors.New("function not found:" + fun)
	}
	var result goja.Value
	var err error
	if args == nil {
		result, err = engine.RunNative(test)
	} else {
		jsArgs := make([]goja.Value, 0)
		for _, arg := range args {
			jsArgs = append(jsArgs, engine.Runtime.ToValue(arg))
		}
		result, err = engine.RunNative(test, jsArgs...)
	}
	if err != nil {
		return nil, err
	}
	return ResolveResult(result)
}

func calcMd5(reader io.Reader) string {
	// Open a new hash interface to write to
	hash := md5.New()

	// Copy the file in the hash interface and check for any error
	if _, err := io.Copy(hash, reader); err != nil {
		return ""
	}
	return hex.EncodeToString(hash.Sum(nil))
}
