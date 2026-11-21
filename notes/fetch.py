import json,subprocess,sys,base64,re,collections
for job in sys.argv[1:]:
    out=subprocess.run(["gh","api",f"repos/BrainEno/where-is-school/check-runs/{job}/annotations?per_page=100"],capture_output=True,text=True).stdout
    parts=collections.defaultdict(dict); totals={}
    for a in json.loads(out):
        m=re.match(r"frame (\S+) part (\d+)/(\d+)",a.get("title") or "")
        if m:
            parts[m[1]][int(m[2])]=a["message"].strip(); totals[m[1]]=int(m[3])
    for f,d in parts.items():
        if len(d)!=totals[f]: print("incomplete",f,len(d),totals[f]); continue
        open("notes/frames/"+f,"wb").write(base64.b64decode("".join(d[i] for i in range(1,totals[f]+1))))
        print("wrote",f)
