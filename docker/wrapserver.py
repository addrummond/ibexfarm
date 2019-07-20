import base64
from BaseHTTPServer import HTTPServer
import errno
import imp
import os
import os.path
import sets
from SimpleHTTPServer import SimpleHTTPRequestHandler
from SocketServer import ThreadingMixIn
import sys
import tempfile
import threading
import time
import urlparse

def WRAPSERVER_clear_globals(imported_modules):
    specials = sets.Set([
        '__builtins__', '__name__', '__doc__', '__package__',
    ])
    for k in globals().keys():
        if not k.startswith("WRAPSERVER_") and k not in specials and k not in imported_modules:
            del globals()[k]

# thunk a module so that initialization code in the global scope doesn't get
# executed by imp.load_source
def WRAPSERVER_thunk_module(source):
    out = [ "def module_thunk():",
            "    __name__ = '__main__'"
          ]
    lines = source.split('\n')
    for l in lines:
        out.append("    " + l)

    with tempfile.NamedTemporaryFile(delete=False) as temp:
        for l in out:
            temp.write(l)
            temp.write('\n')

    return temp.name

def WRAPSERVER_get_module(path, cached_module_holder, imported_modules):
    def load_it():
        with open(path) as f:
            src = f.read()
            temp_name = WRAPSERVER_thunk_module(src)
            n = "server_py_module_" + base64.b64encode(path).replace('=', '.')
            m = imp.load_source(n, temp_name)
            os.remove(temp_name)
            cached_module_holder[0] = (m, time.gmtime())
    if cached_module_holder[0] is None:
        load_it()
    else:
        m, t = cached_module_holder[0]
        ft = os.path.getmtime(path)
        if ft > t:
            load_it()

    return cached_module_holder[0][0]

def WRAPSERVER_exec_as_cgi(thunked_module, env, cgi_exec_mutex, imported_modules):
    cgi_exec_mutex.acquire()

    try:
        WRAPSERVER_clear_globals(imported_modules)

        current_env = os.environ.copy()
        for k in os.environ.keys():
            del os.environ[k]
        for k, v in env.iteritems():
            os.environ[k] = v

        # We "redirect" stdout to a temporary file.
        tempfn = None
        with tempfile.NamedTemporaryFile(delete=False) as temp:
            real_stdout = sys.stdout
            sys.stdout = temp
            thunked_module.module_thunk()
            sys.stdout = real_stdout
            tempfn = temp.name

        for k in os.environ.keys():
            del os.environ[k]
        for k, v in current_env.iteritems():
            os.environ[k] = v

        contents = open(tempfn).read()
        os.remove(tempfn)

        return contents
    finally:
        cgi_exec_mutex.release()

class WRAPSERVER_ThreadingServer(ThreadingMixIn, HTTPServer):
    pass

def WRAPSERVER_make_request_handler(module_path, cgi_exec_mutex, cached_module_holder, imported_modules):
    class RequestHandler(SimpleHTTPRequestHandler):
        def send404(self, m=None):
            self.send_response(404)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write("404 not found" + (': ' + m if m is not None else ''))

        def send500(self):
            self.send_response(500)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write("500 internal server error")

        def do_GET(self):
            pu = urlparse.urlparse(self.path)
            q = urlparse.parse_qs(pu.query)

            m = None
            try:
                m = WRAPSERVER_get_module(module_path, cached_module_holder, imported_modules)
                tempfn = None
                contents = WRAPSERVER_exec_as_cgi(m, q, cgi_exec_mutex, imported_modules)
                self.send_response(200)
                self.wfile.write(contents)

            except IOError as e:
                if e.errno == errno.ENOENT:
                    self.send404()
                else:
                    sys.stderr.write(str(e) + '\n')
                    self.send500()
                return
            except Exception as e:
                sys.stderr.write(str(e) + '\n')
                self.send500()
                return

    return RequestHandler

if __name__ == '__main__':
    port = os.environ.get('IBEX_SERVER_PY_PROXY_PORT')
    try:
        port = int(port)
    except TypeError, ValueError:
        sys.stderr.write("Could not obtain port from IBEX_SERVER_PY_PROXY_PORT env var\n")
        sys.exit(1)
    server_py = os.environ.get('IBEX_SERVER_PY_PATH')
    if server_py is None:
        sys.stderr.write("IBEX_SERVER_PY_PATH not set")
        sys.exit(1)

    cgi_exec_mutex = threading.Lock()
    cached_module_holder = [None]
    imported_modules = sets.Set(sys.modules.keys())
    WRAPSERVER_ThreadingServer(
        ('', port),
        WRAPSERVER_make_request_handler(server_py, cgi_exec_mutex, cached_module_holder, imported_modules)
    ).serve_forever()