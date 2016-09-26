import re
import os


targets = ['lua']
exclude = ['base.lua', 'urls.lua', 'utils.lua', 'manage.lua', 'view.lua']
repls = [
(r'\bdict\b','utils.dict'), 
(r'\blist\b','utils.list'), 
(r'\btable_has\b','utils.table_has'), 
(r'\bto_html_attrs\b','utils.to_html_attrs'), 
(r'\bstring_strip\b','utils.string_strip'), 
(r'\bis_empty_value\b','utils.is_empty_value'), 
(r'\bdict_update\b','utils.dict_update'), 
(r'\blist_extend\b','utils.list_extend'), 
(r'\breversed_metatables\b','utils.reversed_metatables'), 
(r'\bwalk_metatables\b','utils.walk_metatables'), 
(r'\bsorted\b','utils.sorted'), 
(r'\bcurry\b','utils.curry'), 
(r'\bserialize_basetype\b','utils.serialize_basetype'), 
(r'\bserialize_andkwargs\b','utils.serialize_andkwargs'), 
(r'\bserialize_attrs\b','utils.serialize_attrs'), 
(r'\bserialize_columns\b','utils.serialize_columns'), 
    ]
def replace(go=False):
    hits = {}
    for root,dirs,files in os.walk(os.getcwd()):
        for filespath in files:
            p = os.path.join(root,filespath)
            if '.' not in p or p.rsplit('.', 1)[1] not in targets:
                continue
            if filespath in exclude:
                continue
            if 'bak\\' in p or 'utils\\' in p:
                continue
            res = []
            with open(p, encoding='u8') as f:
                for i, line in enumerate(f):
                    if 'local ' in line or '--' in line:
                        res.append(line)
                        continue
                    for pat, new in repls:
                        if re.search(pat, line):
                            if p not in hits:
                                hits[p] = []
                            hits[p].append((i, line))
                            line = re.sub(pat, new, line)
                            break
                    res.append(line)
            if go:
                open(p,'w',encoding='u8').write(''.join(res))

    for path, lines in hits.items():
        print(path)
        for i, line in lines:
            print(str(i+1).rjust(6), line.strip())


replace()


    
