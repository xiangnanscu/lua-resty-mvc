import re
import os


def replace(go=False):
    for old, new in [('resty.model','resty.mvc')]:
        arr = []
        for root,dirs,files in os.walk(os.getcwd()):
            for filespath in files:
                change = False
                p = os.path.join(root,filespath)
                if p[-3:] not in ['lua','tml']:
                    continue
                with open(p,encoding='u8') as f:
                    s = f.read()
                    if old in s:
                        change = True

                if change:
                    print(p)
                    if go:
                        open(p,'w',encoding='u8').write(s.replace(old, new))
                        print('changed')
                    

def search():
    for old in ['resty.model','resty.mvc']:
        arr = []
        for root,dirs,files in os.walk(os.getcwd()):
            for filespath in files:
                p = os.path.join(root,filespath)
                if p[-3:] not in ['lua','tml']:
                    continue
                with open(p,encoding='u8') as f:
                    s = f.read()
                    if old in s:
                        print(p)

replace(1)


    
