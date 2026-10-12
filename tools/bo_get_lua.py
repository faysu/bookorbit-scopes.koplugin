# Prueba en el Mac: GET al catálogo de BookOrbit con las credenciales de una
# copia de settings.reader.lua del Kindle; imprime la respuesta como tabla Lua.
# Uso: python3 -I bo_get_lua.py <settings.reader.lua> <ruta bajo /api/v1>
# Solo lectura. No imprime credenciales.
import json, re, sys, urllib.error, urllib.request

def lua(v):
    if v is None: return "nil"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list): return "{" + ",".join(lua(x) for x in v) + "}"
    return "{" + ",".join("[%s]=%s" % (lua(k), lua(x)) for k, x in v.items() if x is not None) + "}"

txt = open(sys.argv[1], encoding="utf-8").read()
blk = txt[txt.index('["bookorbit"] = {'):]
def field(name):
    m = re.search(r'^        \["%s"\] = "([^"]*)"' % name, blk, re.M)
    return m.group(1) if m else None
base = field("server_url").rstrip("/")
if not base.endswith("/api/v1"): base += "/api/v1"
req = urllib.request.Request(base + sys.argv[2], headers={
    "x-auth-user": field("username"), "x-auth-key": field("userkey"), "accept": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        print("return " + lua(json.load(r)))
except urllib.error.HTTPError as e:
    print("return nil, %d" % e.code)
