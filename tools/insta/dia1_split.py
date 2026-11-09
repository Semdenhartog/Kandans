from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import numpy as np
F='assets/fonts/'
W,H=1080,1350
src=Image.open('site/foto/duin.jpg').convert('RGB')
cx=int(src.width*0.515); w=int(src.height*W/H)
crop=src.crop((cx-w//2,0,cx+w//2,src.height)).resize((W,H),Image.LANCZOS)
crop=crop.filter(ImageFilter.UnsharpMask(2,60,2))
a=np.asarray(crop).astype(float)/255
lum=a@[0.299,0.587,0.114]
rng=np.random.default_rng(7)
# ---- regen-helft
r=a*0.55+lum[...,None]*0.45          # minder kleur
r=r*np.array([0.80,0.88,1.00])        # koel
r=0.04+r*0.66                         # donkerder
yy=np.linspace(0,1,H)[:,None,None]
r=r*(1-0.25*(1-yy))+np.array([0.55,0.6,0.66])*0.25*(1-yy)  # grijze lucht/waas
# natte grond: donkerder onderin met glans
wet=np.clip((yy-0.45)/0.55,0,1)
r=r*(1-0.38*wet)
# regenstrepen
rain=Image.new('L',(W,H),0); d=ImageDraw.Draw(rain)
for _ in range(2600):
    x=rng.uniform(-100,W); y=rng.uniform(-100,H); L=rng.uniform(18,55)*rng.choice([1,1,1,1.8]); b=int(rng.uniform(25,95))
    d.line((x,y,x+L*0.16,y+L),fill=b,width=1)
rain=rain.filter(ImageFilter.GaussianBlur(0.9))
# kleine spatjes op de grond
for _ in range(900):
    x=rng.uniform(0,W); y=rng.uniform(H*0.55,H); rr=rng.uniform(0.8,2.2)
    d.ellipse((x-rr*2,y-rr*0.6,x+rr*2,y+rr*0.6),fill=int(rng.uniform(30,90)))
rn=np.asarray(rain).astype(float)/255
r=np.clip(r+rn[...,None]*0.28,0,1)
# ---- droge helft: warm, gouden laag licht
g=a.copy()
g=np.clip((g-0.5)*1.08+0.5,0,1)
g=g*np.array([1.05,1.00,0.90])
sky=np.clip(1-yy/0.45,0,1)[...,0][...,None]*np.clip((lum[...,None]-0.55)/0.3,0,1)
g=g*(1-0.35*sky)+np.array([0.70,0.80,0.90])*0.35*sky
glow=np.exp(-(((np.arange(W)[None,:]-W*0.62)/420)**2+((np.arange(H)[:,None]-H*0.30)/380)**2))
g=np.clip(g+glow[...,None]*np.array([0.10,0.07,0.02]),0,1)
# ---- samenvoegen
out=g.copy(); out[:,:W//2]=r[:,:W//2]
# korrel + vignet
out=out+rng.normal(0,0.018,out.shape)
X,Y=np.meshgrid(np.linspace(-1,1,W),np.linspace(-1,1,H))
out=out*(1-0.18*np.clip(X**2+Y**2-0.3,0,1))[...,None]
# verloop onderaan voor tekst
bot=np.clip((yy-0.55)/0.40,0,1)**1.1
out=out*(1-0.86*bot)+np.array([26,20,16])/255*0.86*bot
im=Image.fromarray((np.clip(out,0,1)*255).astype('uint8'))
dr=ImageDraw.Draw(im)
CREAM=(241,233,220); GOLD=(217,191,146); INK=(26,20,16)
# gouden splitlijn
dr.rectangle((W//2-2,0,W//2+1,H),fill=GOLD)
kop=ImageFont.truetype(F+'Saira-ExtraBold.ttf',104)
mono=ImageFont.truetype(F+'DejaVuSansMono.ttf',26)
lbl=ImageFont.truetype(F+'DejaVuSansMono.ttf',32)
tijd=ImageFont.truetype(F+'Saira-ExtraBold.ttf',150)
# kop bovenaan, gecentreerd, donker op lichte lucht
t1="Zelfde rondje."
tw=dr.textlength(t1,font=kop)
# zachte lichte waas achter kop voor leesbaarheid
dr.text(((W-tw)/2,128),t1,font=kop,fill=INK)
# midden-label
lab="45 MIN LATER"; lw=dr.textlength(lab,font=mono)
bx0=W//2-lw/2-26; by=H*0.47
dr.rectangle((bx0-22,by-8,W//2+lw/2+26,by+44),fill=INK)
dr.rectangle((bx0-22,by-8,bx0+8,by+44),fill=GOLD)
dr.text((bx0+22,by+3),lab,font=mono,fill=GOLD)
# tijden
def blok(cx,label,t,col):
    label=' '.join(label); lw=dr.textlength(label,font=lbl); dr.text((cx-lw/2,H-336),label,font=lbl,fill=col)
    tw=dr.textlength(t,font=tijd); dr.text((cx-tw/2,H-300),t,font=tijd,fill=CREAM)
blok(W*0.25,"REGEN","15:50",(176,192,204))
blok(W*0.75,"DROOG","16:35",GOLD)
dr.text((60,H-64),"kadans.app",font=mono,fill=CREAM)
s="01 / 04"; dr.text((W-60-dr.textlength(s,font=mono),60),s,font=mono,fill=INK)
im.save('kadans_proef_01.jpg',quality=94)
im.resize((360,450),Image.LANCZOS).save('thumb.jpg')
