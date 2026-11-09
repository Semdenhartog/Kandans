from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
F='assets/fonts/'
W,H=1080,1350
CREAM=(241,233,220); GOLD=(217,191,146); INK=(26,20,16); PAPER=(239,231,217); COOL=(143,163,176); MUTE=(120,108,96)
rng=np.random.default_rng(3)
def f(n,s): return ImageFont.truetype(F+n,s)
kop=f('Saira-ExtraBold.ttf',92); mono=f('DejaVuSansMono.ttf',26); lbl=f('DejaVuSansMono.ttf',22)
body=f('DMSans-Medium.ttf',36)
def grain(im,amt=0.016):
    a=np.asarray(im).astype(float)/255; a=a+rng.normal(0,amt,a.shape)
    return Image.fromarray((np.clip(a,0,1)*255).astype('uint8'))
def chrome(dr,n,dark):
    c=INK if not dark else CREAM
    s=f"0{n} / 04"; dr.text((W-60-dr.textlength(s,font=mono),60),s,font=mono,fill=c)
    dr.text((60,H-64),"kadans.app",font=mono,fill=c)
def lines(dr,x,y,parts,font,lh):
    for ln in parts:
        xx=x
        for t,c in ln: dr.text((xx,y),t,font=font,fill=c); xx+=dr.textlength(t,font=font)
        y+=lh
    return y
def photo(path,cxr=0.5):
    src=Image.open(path).convert('RGB'); w=int(src.height*W/H); cx=int(src.width*cxr)
    cx=min(max(cx,w//2),src.width-w//2)
    return src.crop((cx-w//2,0,cx+w//2,src.height)).resize((W,H),Image.LANCZOS)

# ---------- 02: weerbalk op papier ----------
im=Image.new('RGB',(W,H),PAPER); dr=ImageDraw.Draw(im)
dr.text((72,150),"02  ZELFDE MIDDAG",font=mono,fill=MUTE)
y=lines(dr,72,196,[[("Het weer wisselt",INK)],[("per ",INK),("kwartier.",(176,140,84))]],kop,96)
# grafiek
times=[15.0+i*0.25 for i in range(11)]  # 15:00..17:30
rain=[2.1,2.6,3.2,2.4,2.8,0.7,0,0,0,0,0]
wind=[30,32,31,29,27,24,18,13,11,10,11]
gx0,gx1,gy=110,1000,980; bw=(gx1-gx0)/len(times)
dr.line((gx0,gy,gx1,gy),fill=(200,188,170),width=2)
best=7  # 16:45? -> index for 16:35 between 6 and 7
for i,(t,r) in enumerate(zip(times,rain)):
    x=gx0+i*bw+10; h=r*110
    if r>0: dr.rounded_rectangle((x,gy-h,x+bw-20,gy),radius=8,fill=COOL)
    else: dr.rounded_rectangle((x,gy-14,x+bw-20,gy),radius=6,fill=(222,206,178))
    if i%2==0:
        hh=int(t); mm=int(round((t-hh)*60)); s=f"{hh}:{mm:02d}"
        dr.text((x+(bw-20)/2-dr.textlength(s,font=lbl)/2,gy+18),s,font=lbl,fill=MUTE)
# markers
def marker(tval,label,col,txtcol,top):
    x=gx0+(tval-15.0)/0.25*bw+10
    dr.line((x,top+56,x,gy),fill=col,width=3)
    w=dr.textlength(label,font=mono)+44
    dr.rectangle((x-w/2,top,x+w/2,top+50),fill=col)
    dr.text((x-w/2+22,top+11),label,font=mono,fill=txtcol)
marker(15.833,"15:50 REGEN",(80,96,108),CREAM,560)
marker(16.583,"16:35 DROOG",INK,GOLD,560)
dr.rectangle((gx0+(16.583-15)/0.25*bw+bw/2-3-0,556,gx0+(16.583-15)/0.25*bw+bw/2+3,556),fill=GOLD)
# legenda
dr.rounded_rectangle((110,1090,134,1114),radius=5,fill=COOL); dr.text((148,1086),"regen per kwartier",font=f('DMSans-Medium.ttf',28),fill=MUTE)
dr.text((110,1150),"Wind zakt van 31 naar 13 km/u.",font=body,fill=INK)
dr.text((110,1196),"Voorbeeld van een novembermiddag.",font=f('DMSans-Regular.ttf',26),fill=MUTE)
chrome(dr,2,False)
grain(im,0.012).save('kadans_proef_02.jpg',quality=94)

# ---------- 03: app in strak toestel ----------
bg=photo('site/foto/heide.jpg',0.62).filter(ImageFilter.GaussianBlur(18))
a=np.asarray(bg).astype(float)/255; a=a*0.42+np.array([26,20,16])/255*0.58*0.6
im=Image.fromarray((np.clip(a,0,1)*255).astype('uint8')); dr=ImageDraw.Draw(im)
dr.text((72,140),"03  WAT KADANS DOET",font=mono,fill=GOLD)
lines(dr,72,186,[[("Kadans rekent",CREAM)],[("het ",CREAM),("voor je uit.",GOLD)]],kop,96)
scr0=Image.open('site/app/vandaag.jpg').convert('RGB').crop((14,14,526,1199))
BAR=40; topc=scr0.crop((0,0,scr0.width,6)).resize((1,1)).getpixel((0,0))
scr=Image.new('RGB',(scr0.width,scr0.height+BAR),topc); scr.paste(scr0,(0,BAR))
bd=ImageDraw.Draw(scr); sf=f('DMSans-SemiBold.ttf',17)
bd.text((24,10),'16:02',font=sf,fill=(240,236,228))
for q in range(4): bd.rectangle((scr.width-64+q*6,27-4*q,scr.width-60+q*6,30),fill=(240,236,228))
bd.rounded_rectangle((scr.width-36,14,scr.width-14,27),radius=3,outline=(240,236,228),width=2); bd.rectangle((scr.width-33,17,scr.width-21,24),fill=(240,236,228))
pw=332; sw=pw-20; sh=int(sw*scr.height/scr.width); ph=sh+20
px=(W-pw)//2; py=402
S=3
ph_img=Image.new('RGBA',(pw*S,ph*S),(0,0,0,0)); pd=ImageDraw.Draw(ph_img)
pd.rounded_rectangle((0,0,pw*S-1,ph*S-1),radius=46*S,fill=(12,12,14,255))
pd.rounded_rectangle((2*S,2*S,pw*S-3*S,ph*S-3*S),radius=44*S,outline=(60,58,56,255),width=2*S)
sc=scr.resize((sw*S,sh*S),Image.LANCZOS)
m=Image.new('L',sc.size,0); ImageDraw.Draw(m).rounded_rectangle((0,0,sc.width-1,sc.height-1),radius=36*S,fill=255)
ph_img.paste(sc,(10*S,10*S),m)
pd.ellipse((pw*S/2-7*S,17*S,pw*S/2+7*S,31*S),fill=(10,10,12,255))
ph_img=ph_img.resize((pw,ph),Image.LANCZOS)
# schaduw
sh_l=Image.new('L',(W,H),0); ImageDraw.Draw(sh_l).rounded_rectangle((px+20,py+40,px+pw-20,py+ph+30),radius=60,fill=170)
sh_l=sh_l.filter(ImageFilter.GaussianBlur(40))
im.paste((8,6,5),(0,0),sh_l)
im.paste(ph_img,(px,py),ph_img)
dr=ImageDraw.Draw(im)
# gouden ring om 16:35
k=sw/scr.width; rx0=px+10+(50-14)*k; ry0=py+10+(436-14+BAR)*k; rx1=px+10+(300-14)*k; ry1=py+10+(512-14+BAR)*k
dr.rounded_rectangle((rx0-10,ry0-8,rx1+10,ry1+8),radius=18,outline=GOLD,width=4)
dr.line((rx1+10,(ry0+ry1)/2,px+pw+30,(ry0+ry1)/2),fill=GOLD,width=3)
dr.rectangle((px+pw+30,(ry0+ry1)/2-7,px+pw+44,(ry0+ry1)/2+7),fill=GOLD)
t1="BESTE"; t2="MOMENT"
dr.text((px+pw+30,(ry0+ry1)/2+18),t1,font=lbl,fill=GOLD); dr.text((px+pw+30,(ry0+ry1)/2+46),t2,font=lbl,fill=GOLD)
im=im.crop((0,0,W,H))
# onderrand: verloop + tekst
a=np.asarray(im).astype(float)/255; yy=np.linspace(0,1,H)[:,None,None]
bot=np.clip((yy-0.80)/0.2,0,1); a=a*(1-0.85*bot)+np.array([26,20,16])/255*0.85*bot
im=Image.fromarray((a*255).astype('uint8')); dr=ImageDraw.Draw(im)
s="WEER · WIND · LICHT · JOUW TEMPO"; dr.text(((W-dr.textlength(s,font=mono))/2,H-140),s,font=mono,fill=CREAM)
chrome(dr,3,True)
grain(im,0.012).save('kadans_proef_03.jpg',quality=94)

# ---------- 04: CTA op heide ----------
im=photo('site/foto/heide.jpg',0.62).filter(ImageFilter.UnsharpMask(2,50,2))
a=np.asarray(im).astype(float)/255
a=np.clip((a-0.5)*1.06+0.5,0,1)*np.array([1.05,1.0,0.88])
yy=np.linspace(0,1,H)[:,None,None]
top=np.clip(1-yy/0.42,0,1)**1.4; bot=np.clip((yy-0.50)/0.5,0,1)**1.1
a=a*(1-0.55*top)+np.array([26,20,16])/255*0.55*top
a=a*(1-0.88*bot)+np.array([26,20,16])/255*0.88*bot
X,Y=np.meshgrid(np.linspace(-1,1,W),np.linspace(-1,1,H)); a=a*(1-0.2*np.clip(X**2+Y**2-0.3,0,1))[...,None]
im=Image.fromarray((np.clip(a,0,1)*255).astype('uint8')); dr=ImageDraw.Draw(im)
dr.text((72,140),"04  TESTERS GEZOCHT",font=mono,fill=GOLD)
y=lines(dr,72,880,[[("Jouw rondje.",CREAM)],[("Beter moment.",GOLD)]],f('Saira-ExtraBold.ttf',96),100)
dr.text((72,y+24),"Stuur WEER en je krijgt de testlink.",font=body,fill=CREAM)
# knop-stijl: donker blok + goud vierkant
bx,by=72,y+92; bt="STUUR WEER"; bw2=dr.textlength(bt,font=mono)+64
dr.rectangle((bx,by,bx+bw2+58,by+62),fill=(14,11,9)); dr.rectangle((bx+bw2,by,bx+bw2+58,by+62),fill=GOLD)
dr.text((bx+30,by+16),bt,font=mono,fill=CREAM); dr.text((bx+bw2+19,by+12),"→",font=f('DMSans-Bold.ttf',32),fill=INK)
s="NU VOOR ANDROID"; dr.text((W-60-dr.textlength(s,font=lbl),H-60),s,font=lbl,fill=CREAM)
chrome(dr,4,True)
grain(im,0.016).save('kadans_proef_04.jpg',quality=94)
ims=[Image.open(f'kadans_proef_0{i}.jpg').resize((360,450),Image.LANCZOS) for i in range(1,5)]
c=Image.new('RGB',(1440,450)); [c.paste(x,(i*360,0)) for i,x in enumerate(ims)]; c.save('overzicht.jpg')
