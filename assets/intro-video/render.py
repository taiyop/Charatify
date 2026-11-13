"""Render Charatify's Japanese introduction, with reproducible motion graphics."""
import argparse
import functools
import json
import math
import subprocess
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
W, H, FPS = 1920, 1080, 30
INK = '#173F3A'
GREEN = '#248A74'
MINT = '#BCEBD6'
CREAM = '#F6F4EC'
MUTED = '#687E77'
CORAL = '#F18A72'
WHITE = '#FFFFFF'
FONT = '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc'
BOLD = '/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc'
segments = json.loads((ROOT/'script.json').read_text())

@functools.lru_cache(None)
def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)

@functools.lru_cache(256)
def label(text, size=32, color=INK, bold=False):
    f = font(size, bold)
    box = f.getbbox(text)
    out = Image.new('RGBA', (max(1, box[2]+6), size+22))
    ImageDraw.Draw(out).text((0, -box[1]+2), text, font=f, fill=color)
    return out

def txt(im, text, x, y, size=32, color=INK, bold=False):
    tile = label(text, size, color, bold)
    im.paste(tile, (round(x), round(y)), tile)

def center(im, text, x, y, size=32, color=INK, bold=False):
    tile = label(text, size, color, bold)
    im.paste(tile, (round(x-tile.width/2), round(y)), tile)

def box(im, xy, radius=24, fill=WHITE, outline=None, width=2):
    ImageDraw.Draw(im).rounded_rectangle(tuple(round(v) for v in xy), radius, fill, outline, width)

def dot(im, x, y, r, fill):
    ImageDraw.Draw(im).ellipse((x-r,y-r,x+r,y+r), fill)

def line(im, xy, fill=GREEN, width=4):
    ImageDraw.Draw(im).line(xy, fill=fill, width=width, joint='curve')

def pill(im, text, x, y, dark=False, size=22):
    tile = label(text,size,MINT if dark else GREEN,True)
    box(im,(x,y,x+tile.width+40,y+48),24, '#24534B' if dark else '#E4EFE7')
    txt(im,text,x+20,y+11,size,MINT if dark else GREEN,True)

def ease(v):
    v = max(0,min(1,v))
    return 1-(1-v)**3

def bubble_mark(im, x, y, size=60, color=MINT):
    box(im,(x,y,x+size,y+size*.7),size*.22,None,color,3)
    line(im,[(x+size*.65,y+size*.7),(x+size*.55,y+size*.9),(x+size*.4,y+size*.7)],color,3)
    dot(im,x+size*.36,y+size*.35,2,color)
    dot(im,x+size*.66,y+size*.35,2,color)

def backdrop(dark=False):
    yy,xx = np.mgrid[0:H,0:W]
    a = np.exp(-(((xx-1550)/900)**2+((yy-260)/800)**2))
    b = np.exp(-(((xx-250)/1100)**2+((yy-980)/500)**2))
    colors = ([18,49,45],[26,79,65],[25,62,56]) if dark else ([247,246,239],[226,239,224],[242,228,213])
    arr=np.array(colors[0])[None,None,:]+a[:,:,None]*(np.array(colors[1])-colors[0])+b[:,:,None]*(np.array(colors[2])-colors[0])*.6
    return Image.fromarray(np.uint8(np.clip(arr,0,255))).convert('RGBA')

BACKS = [backdrop(False),backdrop(True)]
artpaths = ['01-bubble-cat.png','02-bubble-sprite.png','03-messenger-bird.png']
ART = [Image.open(ROOT.parent/'icon-candidates/v1'/p).convert('RGB') for p in artpaths]

@functools.lru_cache(64)
def artwork(index,size,shape='rounded'):
    a=ART[index].resize((size,size),Image.Resampling.LANCZOS).convert('RGBA')
    mask=Image.new('L',(size,size));d=ImageDraw.Draw(mask)
    if shape=='circle':d.ellipse((0,0,size-1,size-1),fill=255)
    else:d.rounded_rectangle((0,0,size-1,size-1),radius=size*.13 if shape=='rounded' else 2,fill=255)
    a.putalpha(mask)
    return a

def art(im,index,x,y,size,shape='rounded'):
    tile=artwork(index,size,shape);im.paste(tile,(round(x),round(y)),tile)

def notification(im,x,y,w=430,scale=1):
    # This is an explicitly labelled illustration, with a fictional message.
    h=120
    box(im,(x,y,x+w,y+h),20,'#EDF1EB', '#D1DDD6')
    box(im,(x+18,y+20,x+62,y+64),12,GREEN)
    bubble_mark(im,x+27,y+30,26,WHITE)
    txt(im,'リマインダー',x+78,y+18,22,INK,True)
    txt(im,'ひと息つきませんか？',x+78,y+58,24,INK)

def character_notice(im,x,y,size=150,index=0,message='ひと息つきませんか？',shape='rounded'):
    art(im,index,x,y,size,shape)
    bw=455; bh=133; bx=x-bw-22; by=y+7
    box(im,(bx,by,bx+bw,by+bh),22,WHITE,'#D2E2D8')
    ImageDraw.Draw(im).polygon([(bx+bw-2,by+76),(bx+bw+17,by+90),(bx+bw-2,by+103)],fill=WHITE)
    txt(im,'リマインダー',bx+23,by+19,21,GREEN,True)
    txt(im,message,bx+23,by+62,27,INK)

def chrome(im, scene, dark=False):
    fg=MINT if dark else GREEN
    bubble_mark(im,94,62,42,fg)
    txt(im,'Charatify',156,63,28,WHITE if dark else INK,True)
    txt(im,'macOS NOTIFICATION COMPANION',1260,72,18,fg)
    line(im,[(96,132),(1824,132)],'#346055' if dark else '#D7E1D7',1)
    txt(im,f'0{scene+1} / 06',96,958,20,fg,True)
    for j in range(6):
        box(im,(1640+j*31,968,1660+j*31,973),2,fg if j<=scene else ('#31564E' if dark else '#CCD9CF'))

def monitor(im,x,y,w,h,fill='#EAF1E9'):
    box(im,(x,y,x+w,y+h),26,WHITE,'#B9CBC0',3)
    box(im,(x+13,y+13,x+w-13,y+h-43),16,fill)
    line(im,[(x+w*.5,y+h),(x+w*.5,y+h+37)],'#AAC0B2',10)
    box(im,(x+w*.33,y+h+34,x+w*.67,y+h+45),6,'#AAC0B2')

def header(im, eyebrow, heading, desc, dark=False):
    txt(im,eyebrow,106,180,23,MINT if dark else GREEN,True)
    txt(im,heading,104,235,65,WHITE if dark else INK,True)
    if desc: txt(im,desc,108,335,28,'#B5D5C7' if dark else MUTED)

def static_scene(i):
    dark=i in [0,4,5]
    im=BACKS[int(dark)].copy();chrome(im,i,dark)
    if i==0:
        pill(im,'好きなキャラクターが、通知をお届け。',108,216,True)
        txt(im,'通知に、',103,321,96,WHITE,True)
        txt(im,'あなたらしさを。',103,455,96,WHITE,True)
        txt(im,'Charatify',108,640,55,MINT,True)
        txt(im,'キャラティファイ / macOS メニューバーアプリ',110,725,27,'#B5D5C7')
        txt(im,'キャラクター・通知画面はイメージです',1300,892,19,'#B5D5C7')
    elif i==1:
        txt(im,'01 / NOTIFICATIONS',108,204,23,GREEN,True)
        txt(im,'届いた通知が、',104,285,62,INK,True)
        txt(im,'ひとことに。',104,375,62,INK,True)
        txt(im,'キャラクターと吹き出しで',108,492,29,MUTED)
        txt(im,'メッセージを表示。',108,540,29,MUTED)
        pill(im,'動作イメージ',108,652)
        monitor(im,745,211,1060,604)
        # A deliberately generic desktop: no private data or actual screenshots.
        box(im,(795,293,1395,626),16,'#F9FAF6','#DCE6DD')
        for k in range(3):dot(im,817+21*k,315,5,['#ECA797','#EBD18D','#A9CBB0'][k])
        txt(im,'今日のアイデア',825,359,27,INK,True)
        for yy,ww in [(421,410),(459,320),(497,382),(554,265)]:box(im,(825,yy,825+ww,yy+11),5,'#DDE7DC')
        txt(im,'※ 標準バナーも表示されます。画面上のバナーが読み取り対象です。',748,890,21,MUTED)
    elif i==2:
        header(im,'02 / MAKE IT YOURS','画像も、動画も。あなた好みに。','キャラクターの見た目を、気軽にカスタマイズ。')
        box(im,(108,415,975,875),30,'#E5EDE1')
        txt(im,'キャラクター例',141,444,20,MUTED)
        for j in range(3):
            art(im,j,139+j*112,735,86)
        txt(im,'画像 / 動画ファイルを選択',510,776,24,MUTED)
        for j,(num,title,body) in enumerate([
            ('01','画像を選ぶ','透過PNG・JPEG・HEIC など'),
            ('02','動画を選ぶ','MP4・MOV・M4V / 無音でループ'),
            ('03','スタイルを選ぶ','円形・角丸・枠線・影を調整')]):
            yy=432+j*147
            pill(im,num,1053,yy+5)
            txt(im,title,1156,yy+1,32,INK,True)
            txt(im,body,1158,yy+56,25,MUTED)
        pill(im,'設定のイメージ',1536,825)
    elif i==3:
        header(im,'03 / FIND YOUR PLACE','好きな画面。好きな場所。','ディスプレイを指定して、9つの位置やドラッグで配置。')
        monitor(im,115,431,1060,393)
        monitor(im,1230,511,570,313,'#E4EDDF')
        for col in range(3):
            for row in range(3):
                dot(im,181+col*453,477+row*122,6,'#BACDBF')
        pill(im,'メインディスプレイ',158,844)
        pill(im,'もうひとつのディスプレイ',1254,866)
        txt(im,'通知が届いたときだけ、表示。',1242,422,29,INK,True)
        txt(im,'配置のイメージ',1580,186,21,MUTED)
    elif i==4:
        header(im,'04 / STAYS ON YOUR MAC','通知本文は、Macの中だけ。','通知の内容はメモリ上だけで処理します。',True)
        for j,(title,body) in enumerate([
            ('保存しない','本文のディスク保存なし'),
            ('送信しない','本文のネットワーク送信なし'),
            ('ローカルで処理','AI・サーバー不要')]):
            x=108+j*578
            box(im,(x,455,x+545,819),28,'#214B42','#3B6456')
            # Small visual metaphor: document, outbound arrow, device.
            if j==0:
                box(im,(x+55,509,x+123,590),9,None,MINT,4)
                line(im,[(x+71,535),(x+106,535)],MINT,3)
                line(im,[(x+71,551),(x+101,551)],MINT,3)
                line(im,[(x+44,603),(x+139,497)],CORAL,5)
            elif j==1:
                line(im,[(x+56,574),(x+125,520),(x+103,520),(x+125,520),(x+125,542)],MINT,5)
                line(im,[(x+44,598),(x+143,496)],CORAL,5)
            else:
                box(im,(x+43,514,x+147,581),9,None,MINT,4)
                line(im,[(x+25,595),(x+165,595)],MINT,5)
            txt(im,title,x+44,649,40,WHITE,True)
            txt(im,body,x+44,727,24,'#B5D5C7')
        txt(im,'キャラクターファイルと設定は、このMacに保存されます。',110,872,23,'#B5D5C7')
    else:
        pill(im,'はじめる準備は、シンプル。',108,185,True)
        for j,(num,title) in enumerate([('1','権限を許可'),('2','キャラクターを選択'),('3','表示をテスト')]):
            x=108+j*578
            box(im,(x,285,x+545,418),22,'#234F43','#3A6555')
            txt(im,num,x+25,324,34,MINT,True)
            txt(im,title,x+82,327,31,WHITE,True)
        center(im,'Charatify',960,513,90,WHITE,True)
        center(im,'通知に、あなたらしさを。',960,656,55,MINT,True)
        center(im,'macOS 14以降 / アクセシビリティ権限が必要',960,784,26,'#B5D5C7')
        center(im,'集中モードで抑制された通知や、非表示の本文は取得できません。',960,853,23,'#B5D5C7')
    return im

BASES=[static_scene(i) for i in range(6)]

def compose(i,t,duration):
    im=BASES[i].copy()
    if i==0:
        k=ease((t-.15)/.8)
        y=285+18*math.sin(t*1.2)
        art(im,0,1291,y+50*(1-k),376)
        if t>.9:character_notice(im,1450,700,120,message='ひと息つきませんか？')
        dot(im,1724,277+8*math.sin(t),10,CORAL)
        dot(im,1219,644+10*math.sin(t*.8),6,MINT)
    elif i==1:
        if t>.65:
            dx=32*(1-ease((t-.65)/.45))
            notification(im,1345+dx,249,425)
        if t>1.7:
            dy=28*(1-ease((t-1.7)/.6))
            character_notice(im,1569,598+dy,160)
        if t>2.5:
            pill(im,'同じメッセージを、吹き出しに。',877,732)
    elif i==2:
        phases=['rounded','circle','square']
        p=min(2,int(t/max(1,duration/3)))
        art(im,p,237,470+5*math.sin(t*1.2),240,phases[p])
        box(im,(139+p*112-5,730,139+p*112+91,826),16,None,GREEN,3)
        txt(im,['角丸','円形','四角'][p],552,531,44,INK,True)
        txt(im,'形・枠線・影',552,604,27,MUTED)
        if p==1:ImageDraw.Draw(im).ellipse((234,467,479,712),outline=CORAL,width=5)
    elif i==3:
        q=t/duration
        if q<.35:x,y=1013,674
        elif q<.65:
            v=ease((q-.35)/.14);x,y=1013+(193-1013)*v,674+(494-674)*v
        else:
            v=ease((q-.65)/.14);x,y=193+(1650-193)*v,494+(641-494)*v
        art(im,0,x,y,112)
        box(im,(x-6,y-6,x+118,y+118),20,None,GREEN,3)
        # Cursor is only used to illustrate placement, never a live capture.
        ImageDraw.Draw(im).polygon([(x+76,y+80),(x+76,y+119),(x+87,y+109),(x+96,y+127),(x+104,y+123),(x+94,y+105),(x+109,y+103)],INK)
    elif i==4:
        # Subtle staggered dots reinforce the three promises.
        for j in range(3):
            if t>.35+j*.6:dot(im,598+j*578,498,7,MINT)
    else:
        if t>duration*.54:
            dot(im,766,753,5,CORAL);dot(im,1154,753,5,CORAL)
    # Burned-in, high contrast captions stay in a dedicated safe area.
    caps=segments[i]['captions']
    cap=caps[min(len(caps)-1,int(t/duration*len(caps)))]
    tw=label(cap,29,WHITE,False).width
    box(im,(960-tw/2-28,1000,960+tw/2+28,1058),18,'#153B35')
    center(im,cap,960,1014,29,WHITE)
    # Gentle fade at each scene boundary.
    alpha=min(1,t/.28,(duration-t)/.28)
    if alpha<1:
        im=Image.blend(BACKS[int(i in [0,4,5])],im,max(0,alpha))
    return im.convert('RGB')

def probe(path):
    return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)]))

def timing():
    data=[];start=0
    for i in range(6):
        voice=probe(ROOT/f'audio/{i:02}.wav')
        duration=math.ceil(max(7,voice+1.35)*FPS)/FPS
        data.append({'scene':i,'start':start,'duration':duration,'voice_duration':voice,'voice_start':start+.55})
        start+=duration
    (ROOT/'timeline.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
    return data

def srt_time(t):
    ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'

def audio_mix(data):
    rate=48000;total=math.ceil(sum(x['duration'] for x in data)*rate)
    mix=np.zeros((total,2),dtype=np.float64)
    for item in data:
        i=item['scene']
        pcm=subprocess.check_output(['ffmpeg','-v','error','-i',str(ROOT/f'audio/{i:02}.wav'),'-f','f32le','-ac','1','-ar',str(rate),'-'])
        a=np.frombuffer(pcm,np.float32).astype(np.float64)
        rms=np.sqrt(np.mean(a*a));a*=min(2.5,.115/max(.001,rms))
        a=np.tanh(a*1.05)*.85
        offset=round(item['voice_start']*rate)
        mix[offset:offset+len(a),:]+=a[:,None]
    with wave.open(str(ROOT/'Charatify-narration-r1.wav'),'wb') as out:
        out.setnchannels(2);out.setsampwidth(2);out.setframerate(rate)
        out.writeframes((np.clip(mix,-.98,.98)*32767).astype('<i2').tobytes())
    # An original, restrained ambient bed. All tones are synthesized here.
    tt=np.arange(total)/rate
    bed=np.zeros(total)
    chords=[(130.8128,164.8138,195.9977,246.9417),(110,130.8128,164.8138,195.9977),
            (87.3071,130.8128,174.6141,220),(97.9989,146.8324,195.9977,246.9417)]
    for k,start in enumerate(np.arange(0,total/rate,4)):
        n0=int(start*rate);n1=min(total,n0+int(5*rate));t=np.arange(n1-n0)/rate
        env=np.minimum(1,t/1.0)*np.minimum(1,(len(t)/rate-t)/1.3)
        chord=sum(np.sin(2*np.pi*f*t)*.006 for f in chords[k%4])
        bed[n0:n1]+=chord*env
        # A soft bell every four seconds, with a smooth attack.
        bell=(np.sin(2*np.pi*chords[k%4][k%4]*4*t)+.18*np.sin(2*np.pi*chords[k%4][k%4]*8*t))*np.exp(-t*1.5)*np.minimum(1,t/.035)*.013
        bed[n0:n1]+=bell
    fade=np.minimum(1,tt/1.5)*np.minimum(1,(total/rate-tt)/2.2)
    mix+=bed[:,None]*fade[:,None]
    for item in data[1:4]:
        n0=round((item['start']+1.3)*rate);length=int(.44*rate);t=np.arange(length)/rate
        bell=(np.sin(2*np.pi*880*t)+.5*np.sin(2*np.pi*1320*t))*np.exp(-t*11)*np.minimum(1,t/.012)*.025
        mix[n0:n0+length]+=bell[:,None]
    with wave.open(str(ROOT/'narration-and-music.wav'),'wb') as out:
        out.setnchannels(2);out.setsampwidth(2);out.setframerate(rate)
        out.writeframes((np.clip(mix,-.98,.98)*32767).astype('<i2').tobytes())
    cues=[]
    for item in data:
        caps=segments[item['scene']]['captions']
        for j,cap in enumerate(caps):
            start=item['start']+item['duration']*j/len(caps)
            end=item['start']+item['duration']*(j+1)/len(caps)
            cues.append(f'{len(cues)+1}\n{srt_time(start)} --> {srt_time(end)}\n{cap}\n')
    (ROOT/'Charatify-intro-ja.srt').write_text('\n'.join(cues))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--preview',action='store_true');args=parser.parse_args()
    if args.preview:
        thumbs=[]
        for i in range(6):
            im=compose(i,4,9);im.save(ROOT/f'work/scene-{i+1}.png');thumbs.append(im.resize((640,360)))
        sheet=Image.new('RGB',(1280,1080))
        for i,im in enumerate(thumbs):sheet.paste(im,((i%2)*640,(i//2)*360))
        sheet.save(ROOT/'storyboard.jpg',quality=93)
        return
    data=timing();audio_mix(data)
    cmd=['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-',
         '-i',str(ROOT/'narration-and-music.wav'),'-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k',
         '-movflags','+faststart','-metadata','title=Charatify | 通知に、あなたらしさを。','-metadata','comment=Japanese introduction; narration uses お姉さんの声 Canonical r1; illustrated UI.',
         '-shortest',str(ROOT/'Charatify-intro-ja.mp4')]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    try:
        for item in data:
            print(f'Rendering scene {item["scene"]+1}/6 ({item["duration"]:.1f}s)',flush=True)
            for frame in range(round(item['duration']*FPS)):
                proc.stdin.write(compose(item['scene'],frame/FPS,item['duration']).tobytes())
        proc.stdin.close()
        if proc.wait():raise RuntimeError('ffmpeg failed')
    except BaseException:
        proc.kill();raise
    compose(0,3,9).save(ROOT/'poster.jpg',quality=95)
    print(f'Finished: {sum(x["duration"] for x in data):.2f}s',flush=True)

if __name__=='__main__':main()
