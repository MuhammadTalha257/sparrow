(()=>{var $=()=>U(new Float32Array(16));function U(t){return t.fill(0),t[0]=t[5]=t[10]=t[15]=1,t}function N(t,e,a){let r=new Float32Array(16);for(let o=0;o<4;o++)for(let s=0;s<4;s++)r[o*4+s]=e[s]*a[o*4]+e[4+s]*a[o*4+1]+e[8+s]*a[o*4+2]+e[12+s]*a[o*4+3];return t.set(r),t}function ee(t,e,a,r){return U(t),t[12]=e,t[13]=a,t[14]=r,t}function je(t,e,a,r){return U(t),t[0]=e,t[5]=a,t[10]=r,t}function X(t,e,a,r){let o=Math.cos(e),s=Math.sin(e),i=Math.cos(a),n=Math.sin(a),l=Math.cos(r),h=Math.sin(r);return U(t),t[0]=l*i,t[1]=h*i,t[2]=-n,t[4]=l*n*s-h*o,t[5]=h*n*s+l*o,t[6]=i*s,t[8]=l*n*o+h*s,t[9]=h*n*o-l*s,t[10]=i*o,t}function te(t,e,a){let[r,o,s]=e,i=Math.cos(a),n=Math.sin(a),l=1-i;return U(t),t[0]=l*r*r+i,t[1]=l*r*o+n*s,t[2]=l*r*s-n*o,t[4]=l*r*o-n*s,t[5]=l*o*o+i,t[6]=l*o*s+n*r,t[8]=l*r*s+n*o,t[9]=l*o*s-n*r,t[10]=l*s*s+i,t}function ge(t,e){let[a,r,o,s,i,n,l,h,f,p,m,d,u,y,w,b]=e,z=a*n-r*i,R=a*l-o*i,M=a*h-s*i,V=r*l-o*n,L=r*h-s*n,I=o*h-s*l,g=f*y-p*u,j=f*w-m*u,_=f*b-d*u,P=p*w-m*y,B=p*b-d*y,T=m*b-d*w,D=z*T-R*B+M*P+V*_-L*j+I*g;if(!D)return U(t);let x=1/D;return t[0]=(n*T-l*B+h*P)*x,t[1]=(o*B-r*T-s*P)*x,t[2]=(y*I-w*L+b*V)*x,t[3]=(m*L-p*I-d*V)*x,t[4]=(l*_-i*T-h*j)*x,t[5]=(a*T-o*_+s*j)*x,t[6]=(w*M-u*I-b*R)*x,t[7]=(f*I-m*M+d*R)*x,t[8]=(i*B-n*_+h*g)*x,t[9]=(r*_-a*B-s*g)*x,t[10]=(u*L-y*M+b*z)*x,t[11]=(p*M-f*L-d*z)*x,t[12]=(n*j-i*P-l*g)*x,t[13]=(a*P-r*j+o*g)*x,t[14]=(y*R-u*V-w*z)*x,t[15]=(f*V-p*R+m*z)*x,t}function ve(t,e){let[a,r,o]=e;return[t[0]*a+t[4]*r+t[8]*o+t[12],t[1]*a+t[5]*r+t[9]*o+t[13],t[2]*a+t[6]*r+t[10]*o+t[14]]}function be(t,e){let[a,r,o]=e;return[t[0]*a+t[4]*r+t[8]*o,t[1]*a+t[5]*r+t[9]*o,t[2]*a+t[6]*r+t[10]*o]}var E=(t,e,a)=>Math.min(a,Math.max(e,t)),Z=(t,e,a)=>t+(e-t)*a,xe=(t,e,a)=>{let r=E((a-t)/(e-t),0,1);return r*r*(3-2*r)},_e=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;function ae(t){let e=Math.floor(t*4294967295)>>>0||1;return()=>{e=e+1831565813>>>0;let a=e;return a=Math.imul(a^a>>>15,a|1),a^=a+Math.imul(a^a>>>7,a|61),((a^a>>>14)>>>0)/4294967296}}var k=class{constructor(e=0){this.x=e}v=0;step(e,a,r,o){let s=r*Math.PI*2;return this.v+=(s*s*(e-this.x)-2*o*s*this.v)*a,this.x+=this.v*a,this.x}};var vt=[{round:0,open:1,weight:.34},{round:.08,open:.55,weight:.26},{round:.7,open:.85,weight:.24},{round:1,open:.5,weight:.16}],re=class{constructor(e){this.random=e;this.silence=.15+e()*.3}open=0;round=0;age=0;length=0;stress=0;silence=0;syllablesLeft=0;wordsLeft=0;reset(){this.age=this.length=this.open=0,this.syllablesLeft=this.wordsLeft=0,this.silence=.12}update(e){if(this.silence>0){this.silence-=e,this.open=0;return}this.age+=e,this.age>=this.length&&this.next();let a=E(this.age/this.length,0,1);this.open=this.stress*Math.pow(Math.sin(Math.PI*a),.55)}next(){let e=this.random;this.age=0;let a=this.syllablesLeft===0;a&&(this.wordsLeft===0?(this.wordsLeft=3+Math.floor(e()*5),this.silence=this.length>0?.45+e()*.7:0):this.silence=.04+e()*.09,this.wordsLeft--,this.syllablesLeft=1+Math.floor(Math.pow(e(),1.6)*3)),this.syllablesLeft--;let r=a&&e()<.6,o=bt(vt,e());this.length=.12+e()*.13,this.stress=o.open*(r?.85+e()*.15:.5+e()*.35),this.round=o.round}};function bt(t,e){for(let a of t){if(e<a.weight)return a;e-=a.weight}return t[0]}var oe=["idle","thinking","listening","speaking","sleeping","working","error","surprised","celebrating","sad"],A=[...oe,"happy"],Q=Object.fromEntries(A.map((t,e)=>[t,e])),ye={idle:{lid:.06,squint:0,smile:.35,tilt:0,energy:1,flap:.05,glow:[.45,.7,1],exposure:1,wide:0,asym:0},thinking:{lid:.4,squint:0,smile:-.15,tilt:.22,energy:.6,flap:0,glow:[1,.55,.12],exposure:1,wide:0,asym:0},listening:{lid:0,squint:0,smile:.2,tilt:-.08,energy:.8,flap:.05,glow:[.25,1,.5],exposure:1,wide:.15,asym:0},speaking:{lid:.04,squint:.1,smile:.45,tilt:0,energy:1.2,flap:.1,glow:[.35,.82,1],exposure:1,wide:0,asym:0},sleeping:{lid:1,squint:0,smile:0,tilt:0,energy:.35,flap:0,glow:[.08,.09,.18],exposure:.84,wide:0,asym:0},working:{lid:.3,squint:.2,smile:.05,tilt:0,energy:1.3,flap:.18,glow:[.6,.45,1],exposure:1,wide:0,asym:0},error:{lid:.12,squint:.15,smile:-.45,tilt:.1,energy:.9,flap:.25,glow:[1,.16,.12],exposure:.97,wide:.2,asym:1},surprised:{lid:0,squint:0,smile:0,tilt:0,energy:1,flap:.55,glow:[.95,.95,1],exposure:1.04,wide:1,asym:0},celebrating:{lid:0,squint:1,smile:1,tilt:0,energy:1.8,flap:.9,glow:[1,.72,.2],exposure:1.08,wide:0,asym:0},sad:{lid:.42,squint:0,smile:-.85,tilt:-.32,energy:.35,flap:-.12,glow:[.22,.32,.7],exposure:.9,wide:0,asym:0},happy:{lid:0,squint:1,smile:1,tilt:0,energy:1.6,flap:.3,glow:[1,.42,.72],exposure:1.05,wide:0,asym:0}};var xt={float:0,hop:.16,squash:1,snap:1,look:1,snapLook:0,talkSquash:0},se=.11,yt=1.8,ie=class{temperament;state="idle";pointer=null;shown="idle";previous="idle";switched=10;time=0;since=0;random;yaw=new k;pitch=new k;roll=new k;squash=new k;hover;face={lid:new k,squint:new k,smile:new k(.3),tilt:new k,talk:new k,round:new k,gazeX:new k,gazeY:new k,flap:new k,energy:new k(1),exposure:new k(1),wide:new k,asym:new k};weights;glow=[...ye.idle.glow];jump=null;look={yaw:0,pitch:0,x:0,y:0};saccade={x:0,y:0,next:0};nextLook=.6;nextBlink;blinkAge=-1;nextHop;nextSide=4;side=1;nextNod=2.5;shake={start:-10,amount:0,next:0};sigh={start:-10,next:0};reactUntil=-1;speech;lastTalk=0;syllableArmed=!0;matrices={a:$(),b:$()};pose;constructor(e={},a=.5){this.temperament={...xt,...e},this.random=ae(a),this.speech=new re(this.random),this.nextBlink=1+this.random()*3,this.nextHop=6+this.random()*6,this.hover=new k(this.temperament.float),this.weights=Object.fromEntries(A.map(r=>[r,new k(r==="idle"?1:0)])),this.pose={root:$(),minScale:1,lift:0,channels:{yaw:0,pitch:0,roll:0,flap:0,talk:0,energy:1},weights:Object.fromEntries(A.map(r=>[r,r==="idle"?1:0])),expression:"idle",faceA:[0,0,0,0],faceB:[0,0,0,0],faceC:[0,0,1,0],faceD:[0,0,0,0],glow:this.glow,exposure:1,events:[]}}setState(e){e!==this.state&&(this.state=e,this.since=0,e==="speaking"&&this.speech.reset(),this.nextLook=0)}poke(){this.hop(this.temperament.hop*1.5,this.random()<.5?1:-1),this.reactUntil=this.time+yt}update(e){if(!(e>0))return;let a=Math.max(1,Math.ceil(e/(1/120)));for(let r=0;r<a;r++)this.step(e/a)}enter(e,a){let r=this.temperament;e==="surprised"?(this.hop(r.hop*.6,0),this.pitch.v+=1.2,this.startShake(a,.35,1/0)):e==="error"?(this.side=this.random()<.5?1:-1,this.squash.v-=2.5,this.startShake(a,1,a+2+this.random())):e==="celebrating"?this.nextHop=a:e==="sad"&&(this.sigh.next=a+1.2)}startShake(e,a,r){this.shake.start=e,this.shake.amount=a,this.shake.next=r}hop(e,a){if(this.jump)return;let r=this.temperament.float>0;this.jump={age:r?se:0,height:e,spin:a,lean:(this.random()-.5)*.3,air:.42+e*.45+(r?.25:0),landed:!1}}step(e){this.time+=e,this.since+=e,this.switched+=e;let a=this.time,r=this.random,o=this.temperament,s=this.pose.events,i=a<this.reactUntil?"happy":this.state;i!==this.shown&&(this.previous=this.shown,this.shown=i,this.switched=0,s.push(`enter:${i}`),this.enter(i,a));let n=ye[i];a>this.nextLook&&(this.look.yaw=(r()-.5)*.75,this.look.pitch=(r()-.5)*.24,this.look.x=E(this.look.yaw*2.2,-1,1),this.look.y=r()<.3?.6:r()<.2?-.6:0,this.nextLook=a+Z(1.4+r()*2.6,.45+r()*1.1,o.snapLook)),a>this.saccade.next&&(this.saccade.x=(r()-.5)*.22,this.saccade.y=(r()-.5)*.14,this.saccade.next=a+.25+r()*.7);let l=0,h=0,f=0,p=Math.sin(a*1.9)*.008,m=0,d=0,u=0,y=0,w=n.flap,b=1.3,z=.62,R=o.float,M=this.pointer,V=M&&(i==="idle"||i==="listening"||i==="speaking"||i==="surprised");switch(i){case"idle":l=this.look.yaw,h=this.look.pitch,f=-this.look.yaw*.16,m=this.look.x,d=this.look.y,a>this.nextHop&&(this.hop(o.hop*(.9+r()*.4),r()<.35?r()<.5?1:-1:0),this.nextHop=a+7+r()*7);break;case"thinking":{a>this.nextSide&&(this.side=-this.side,this.nextSide=a+3+r()*2);let v=this.side;l=.24*v+Math.sin(a*.9)*.05,h=.17+Math.sin(a*1.3)*.03,f=-.13*v,m=.7*v,d=.8,b=.9;break}case"listening":l=-.14,h=.02,f=.17,m=-.2,a>this.nextNod&&(this.pitch.v-=.9,this.nextNod=a+2+r()*2.5);break;case"speaking":{l=Math.sin(a*.7)*.12,f=Math.sin(a*.9)*.05,this.speech.update(e),u=this.speech.open,y=this.speech.round,h=.04+u*.07,p+=u*.014,w+=Math.sin(a*2.6)*.1,b=1.8;break}case"sleeping":h=-.3,f=.13,l=.06,p=Math.sin(a*1.15)*.016,u=.12+.1*Math.sin(a*1.15),y=.7,R*=.65,b=.55,z=.9,a>this.nextNod&&(this.pitch.v-=.5,this.nextNod=a+5+r()*4);break;case"working":l=Math.sin(a*.8)*.07,h=-.13+Math.abs(Math.sin(a*5.2))*.03,f=Math.sin(a*.6)*.04,m=Math.sin(a*1.6)*.45,d=-.55,w+=Math.sin(a*11)*.06,b=1.6;break;case"error":{a>this.shake.next&&this.startShake(a,.55,2.4+r()*1.4);let v=this.side;f=.16*v,l=-.1*v,h=.05,m=.45*v,d=.3,u=.16,b=1.5;break}case"surprised":h=.1,u=.42,y=1,b=2.2,z=.5;break;case"celebrating":l=Math.sin(a*3.1)*.22,f=Math.sin(a*6.2)*.1,h=.14,u=.6+.12*Math.sin(a*7),y=.05,w+=Math.sin(a*9)*.25,b=2,a>this.nextHop&&(this.hop(o.hop*1.25,r()<.3?r()<.5?1:-1:0),this.nextHop=a+.85+r()*.4);break;case"sad":{a>this.sigh.next&&(this.sigh.start=a,this.sigh.next=a+4+r()*2.5);let v=Math.sin(E((a-this.sigh.start)/1.7,0,1)*Math.PI);h=-.24+v*.1,l=Math.sin(a*.3)*.1,f=.08,m=-.15,d=-.65+v*.3,p+=v*.018,R*=.7,b=.7,z=.85;break}case"happy":l=Math.sin(a*2.2)*.18,f=Math.sin(a*4.4)*.12,h=.12,u=.5+.15*Math.sin(a*8),y=.2,a>this.nextHop&&(this.hop(o.hop*1.05,0),this.nextHop=a+1.05+r()*.4);break}V&&M&&(l=E(M.x,-1,1)*.55,h=E(-M.y,-1,1)*.32+(i==="speaking"?u*.07:0),f=-l*.12+(i==="listening"?.12:0),m=E(M.x*2,-1,1),d=E(-M.y*1.5,-1,1)),i!=="sleeping"&&(m+=this.saccade.x,d+=this.saccade.y),o.float>0&&(p+=Math.sin(a*1.5)*.035);let L=Z(b,b*3.2,o.snapLook)*o.snap,I=Z(z,.95,o.snapLook);this.yaw.step(l*o.look,e,L,I),this.pitch.step(h*o.look,e,L,I),this.roll.step(f,e,b*o.snap,z),this.hover.step(R,e,.6,.8);let g=this.face;g.lid.step(n.lid,e,2.2,.9),g.squint.step(n.squint,e,3,.8),g.smile.step(n.smile,e,2.4,.75),g.tilt.step(n.tilt*this.side,e,1.6,.8),g.talk.step(u,e,14,.8),g.round.step(y,e,6,.8),g.gazeX.step(m,e,7,.85),g.gazeY.step(d,e,7,.85),g.flap.step(w,e,2.4*o.snap,.5),g.energy.step(n.energy,e,.8,1),g.exposure.step(n.exposure,e,.4,1),g.wide.step(n.wide,e,5,.6),g.asym.step(n.asym*this.side,e,3,.8);for(let v of A)this.weights[v].step(v===i?1:0,e,1.6*o.snap,.95);let j=1-Math.exp(-e*4),_=i==="thinking"?.55+.45*Math.sin(a*4.2):i==="speaking"?.6+.6*g.talk.x:i==="working"?.75+.25*Math.sin(a*7):i==="error"?Math.sin(a*7)>0?1.1:.45:1;for(let v=0;v<3;v++)this.glow[v]=Z(this.glow[v],n.glow[v]*_,j);this.syllableArmed&&g.talk.x>.55&&this.lastTalk<=.55&&i==="speaking"&&(s.push("syllable"),this.syllableArmed=!1),g.talk.x<.35&&(this.syllableArmed=!0),this.lastTalk=g.talk.x;let P=0,B=0,T=0,D=0,x=this.jump;if(x)if(x.age+=e,x.age<se)D=.14;else{let v=(x.age-se)/x.air;v<1?(v<.06&&this.squash.x>.05&&(this.squash.v=-2.6),P=4*x.height*v*(1-v),B=x.spin*Math.PI*2*_e(E(v*1.08,0,1)),T=x.lean*Math.sin(v*Math.PI),D=v<.5?-.05:0):x.landed?x.age-se-x.air>.35&&(this.jump=null):(x.landed=!0,o.float===0&&(this.squash.v+=3.2,s.push("land")))}o.float>0&&(D*=.3),this.squash.step(D,e,3.2,.32),a>this.nextBlink&&(this.blinkAge=0,this.nextBlink=a+2.2+r()*3.5,r()<.2&&(this.nextBlink=a+.35));let Le=0;this.blinkAge>=0&&(this.blinkAge+=e,Le=Math.sin(E(this.blinkAge/.17,0,1)*Math.PI),this.blinkAge>.17&&(this.blinkAge=-1));let de=i==="sleeping",Ie=Math.sin(a*(de?1.15:2.1))*(de?.024:.01),Pe=this.squash.x*o.squash+g.talk.x*.05*o.talkSquash,ue=1+Pe*.55-Ie*.5,Be=1-Pe+Ie,Te=P+p+this.hover.x,{a:ut,b:gt}=this.matrices,Y=this.pose.root;ee(Y,0,Te,0),N(Y,Y,X(ut,0,B,T)),N(Y,Y,je(gt,ue,Be,ue));let C=this.pose;C.minScale=Math.min(ue,Be),C.lift=Te,C.expression=i;let G=C.channels,Oe=this.shake.amount*Math.max(0,1-(a-this.shake.start)/.6);G.yaw=this.yaw.x+Math.sin(a*31)*.06*Oe,G.pitch=this.pitch.x,G.roll=this.roll.x+Math.sin(a*38)*.07*Oe,G.flap=g.flap.x,G.talk=g.talk.x,G.energy=g.energy.x;let Ve=0;for(let v of A)Ve+=Math.max(0,this.weights[v].x);for(let v of A)C.weights[v]=Math.max(0,this.weights[v].x)/(Ve||1);C.faceA=[de?0:Le,g.lid.x,g.squint.x,g.smile.x],C.faceB=[g.talk.x,g.gazeX.x,g.gazeY.x,g.tilt.x],C.faceC=[Q[this.shown],Q[this.previous],E(this.switched/.35,0,1),this.switched<.3?1-this.switched/.3:0],C.faceD=[this.since,g.round.x,g.wide.x,g.asym.x],C.exposure=g.exposure.x}};var K=32,wt={z:0,bubble:1,sparkle:2,heart:3,note:4,arc:5,puff:6,ring:7,drop:8,spark:9,mote:10,feather:11,dot:12,exclaim:13,warning:14,confetti:15,cloud:16,star:17,gear:18},De={sleeping:[{glyph:"z",anchor:"top",rate:.55,offset:[.12,.04,.05],spread:.02,velocity:[.07,.13,0],jitter:.015,wobble:.05,life:[3,3.6],size:[.045,.12],rotation:-.2,spin:.12,color:"#7f88ad"}],thinking:[{glyph:"dot",anchor:"top",rate:1.1,offset:[.16,.02,.06],spread:.01,velocity:[.05,.11,0],jitter:.01,wobble:.02,life:[1.5,1.8],size:[.012,.04],color:"#a3abc9"}],listening:[{glyph:"arc",anchor:"ear",rate:1.5,offset:[-.4,0,.04],velocity:[.3,0,0],life:[1.05,1.2],size:[.1,.05],rotation:0,color:"#5cc489"}],syllable:[{glyph:"arc",anchor:"mouth",rate:2,offset:[.1,0,.06],mirror:!0,velocity:[.24,.02,.04],jitter:.02,life:[.55,.7],size:[.03,.085],rotation:0,color:"#6aaee6"}],"enter:happy":[{glyph:"sparkle",anchor:"top",rate:7,spread:.22,velocity:[0,.3,.05],jitter:.4,gravity:.5,drag:1.5,life:[.7,1.1],size:[.06,0],spin:2.4,color:"#ffc94d"},{glyph:"heart",anchor:"top",rate:2,spread:.12,velocity:[0,.32,.05],jitter:.15,wobble:.06,life:[1,1.3],size:[.045,.08],color:"#ff6b8f"}],happy:[{glyph:"sparkle",anchor:"top",rate:2.5,spread:.35,velocity:[0,.14,0],jitter:.1,life:[.6,.9],size:[.045,0],spin:1.6,color:"#ffd166"}],working:[{glyph:"gear",anchor:"top",rate:.7,offset:[.12,.02,.05],spread:.03,velocity:[.05,.1,0],jitter:.02,wobble:.02,life:[2,2.4],size:[.035,.065],spin:2.2,color:"#a99cf0"},{glyph:"dot",anchor:"top",rate:2.2,offset:[-.16,.06,.05],spread:.02,velocity:[-.06,.14,0],jitter:.03,life:[.8,1.1],size:[.015,.006],color:"#c7bfff",glow:!0}],"enter:error":[{glyph:"warning",anchor:"top",rate:1,offset:[.02,.12,.08],velocity:[0,.16,0],drag:2.2,life:[1.5,1.5],size:[.12,.1],color:"#ff4d3d"},{glyph:"spark",anchor:"top",rate:6,offset:[0,0,.05],velocity:[0,.4,0],jitter:1.3,gravity:1.6,life:[.25,.4],size:[.035,.015],color:"#ffd166",glow:!0,align:!0}],error:[{glyph:"puff",anchor:"top",rate:2.2,offset:[.02,.02,0],spread:.04,velocity:[0,.16,0],jitter:.05,wobble:.04,drag:.4,life:[1.3,1.7],size:[.04,.13],color:"#8b8fa3"}],"enter:surprised":[{glyph:"exclaim",anchor:"top",rate:1,offset:[.04,.14,.06],velocity:[0,.3,0],drag:3.5,life:[1.1,1.1],size:[.11,.08],rotation:-.15,color:"#ffcc33"},{glyph:"spark",anchor:"top",rate:8,offset:[0,.02,.04],spread:.04,velocity:[0,.5,0],jitter:1.1,drag:4,life:[.3,.42],size:[.05,.02],color:"#ffe08a",align:!0}],celebrating:[{glyph:"confetti",anchor:"top",rate:2.6,spread:.25,velocity:[0,.7,.05],jitter:.7,gravity:.9,drag:1.4,wobble:.06,life:[1.6,2.2],size:[.03,.026],spin:7,color:"#ff5d8f"},{glyph:"confetti",anchor:"top",rate:2.6,spread:.25,velocity:[0,.7,.05],jitter:.7,gravity:.9,drag:1.4,wobble:.06,life:[1.6,2.2],size:[.03,.026],spin:-6,color:"#ffc933"},{glyph:"confetti",anchor:"top",rate:2.6,spread:.25,velocity:[0,.7,.05],jitter:.7,gravity:.9,drag:1.4,wobble:.06,life:[1.6,2.2],size:[.03,.026],spin:8,color:"#4dc3ff"},{glyph:"confetti",anchor:"top",rate:2.6,spread:.25,velocity:[0,.7,.05],jitter:.7,gravity:.9,drag:1.4,wobble:.06,life:[1.6,2.2],size:[.03,.026],spin:-7,color:"#5ee08f"}],"enter:celebrating":[{glyph:"star",anchor:"top",rate:6,spread:.1,velocity:[0,.55,.05],jitter:.9,gravity:.6,drag:1.6,life:[.8,1.2],size:[.06,.02],spin:2,color:"#ffd23f"}],sad:[{glyph:"cloud",anchor:"top",rate:.42,offset:[-.12,.22,.02],velocity:[0,0,0],wobble:.015,life:[2.6,2.6],size:[.15,.15],color:"#9aa3bd"},{glyph:"drop",anchor:"top",rate:4,offset:[-.12,.16,.03],spread:.08,velocity:[0,-.25,0],gravity:1.2,life:[.45,.6],size:[.018,.014],color:"#6aa8ff",align:!0}],land:[{glyph:"puff",anchor:"feet",rate:7,spread:.1,velocity:[0,.05,0],jitter:.32,drag:3.5,life:[.45,.7],size:[.05,.12],color:"#c4cad9"}]};function kt(t){let e=parseInt(t.replace("#",""),16);return[(e>>16&255)/255,(e>>8&255)/255,(e&255)/255]}function Ne(t,e){return t==="drop"?Math.atan2(e[0],-e[1]):Math.atan2(e[1],e[0])}var ne=class{constructor(e,a){this.character=e;this.random=a;let r=e.spec.fx??{},o=new Set([...Object.keys(De),...Object.keys(r)].filter(s=>s!=="replace"));for(let s of o){let i=r[s]??[],n=r.replace?.includes(s)?i:[...De[s]??[],...i];this.emitters[s]=n.filter(l=>e.anchors[l.anchor])}}a=new Float32Array(K*4);b=new Float32Array(K*4);c=new Float32Array(K*4);count=0;emitters={};carry=new Map;particles=[];update(e,a,r){for(let s of this.emitters[a.expression]??[])this.emitContinuous(s,e*a.weights[a.expression],r);for(let s of this.emitters.ambient??[])this.emitContinuous(s,e,r);for(let s of a.events)for(let i of this.emitters[s]??[])this.burst(i,i.rate,r);let o=[];for(let s of this.particles){if(s.age+=e,s.age>=s.life)continue;let i=s.spec;s.vel[1]-=(i.gravity??0)*e;let n=Math.max(0,1-(i.drag??0)*e);for(let l=0;l<3;l++)s.vel[l]*=n,s.pos[l]+=s.vel[l]*e;i.wobble&&(s.pos[0]+=Math.cos(s.age*3.1+s.seed*6.28)*i.wobble*e*3),s.rot=i.align?Ne(i.glyph,s.vel):s.rot+(i.spin??0)*e,o.push(s)}this.particles=o.slice(-K),this.pack()}emitContinuous(e,a,r){let o=(this.carry.get(e)??this.random())+e.rate*a,s=Math.floor(o);this.carry.set(e,o-s),s>0&&this.burst(e,s,r)}burst(e,a,r){let o=this.character.anchors[e.anchor],s=this.random;for(let i=0;i<a;i++){let n=e.mirror&&i%2===1?-1:1,l=e.offset??[0,0,0],h=e.spread??0,f=[o.at[0]+l[0]*n+(s()-.5)*2*h,o.at[1]+l[1]+(s()-.5)*2*h,o.at[2]+l[2]+(s()-.5)*2*h],p=e.jitter??0,m=[e.velocity[0]*n+(s()-.5)*2*p,e.velocity[1]+(s()-.5)*p,e.velocity[2]+(s()-.5)*2*p];this.particles.push({pos:r.point(o.bone,f),vel:m,age:0,life:e.life[0]+(e.life[1]-e.life[0])*s(),size:e.size,rot:e.align?Ne(e.glyph,m):n<0?Math.PI-(e.rotation??0):(e.rotation??0)+(e.spin?s():0),spec:e,color:kt(e.color),seed:s()})}}pack(){this.count=this.particles.length,this.particles.forEach((e,a)=>{let r=e.age/e.life,o=1-(1-r)*(1-r),s=xe(0,.12,r)*(1-xe(.62,1,r)),i=a*4;this.a.set([e.pos[0],e.pos[1],e.pos[2],e.size[0]+(e.size[1]-e.size[0])*o],i),this.b.set([wt[e.spec.glyph],s,e.rot,e.spec.glow?1:0],i),this.c.set([e.color[0],e.color[1],e.color[2],e.seed],i)})}};function O(t){let e=parseInt(t.replace("#",""),16),a=r=>Math.pow(r/255,2.2);return[a(e>>16&255),a(e>>8&255),a(e&255)]}var c=t=>{let e=Number(t.toFixed(5)).toString();return e.includes(".")||e.includes("e")?e:`${e}.0`},H=t=>`vec2(${c(t[0])}, ${c(t[1])})`,S=t=>`vec3(${c(t[0])}, ${c(t[1])}, ${c(t[2])})`;function He(t){let e=X($(),t[0],t[1],t[2]);return`mat3(${[0,1,2].map(r=>[e[r],e[4+r],e[8+r]]).flat().map(c).join(", ")})`}function Ue(t,e=!1){let a=["vec2 map(vec3 p) {","  vec2 r = vec2(1e9, 0.0);","  vec3 l;"],r=new Set,o=i=>(r.has(i)||(r.add(i),a.push(`  vec3 b${i} = (uBones[${i}] * vec4(p, 1.0)).xyz;`)),`b${i}`);t.spec.parts.forEach((i,n)=>{let l=o(t.boneIndex(i.bone,`parts[${n}]`)),h=i.at??[0,0,0],f=i.rot?`${He(i.rot)} * (${l} - ${S(h)})`:`${l} - ${S(h)}`;a.push(`  l = ${f};`);let p=c(t.materialId(i.material,`parts[${n}]`)),m=e?`if (uReveal.x > ${c(n)}) `:"";if(i.shape==="hem"){a.push(`  ${m}r.x = smax(r.x, ${c(i.y)} + ${c(i.amplitude)} * sin(atan(l.z, l.x) * ${c(i.waves)} + uTime * ${c(i.speed)}) - l.y, ${c(i.blend)});`);return}let d=i.clip?`max(${Ge(i)}, dot(l, ${S(Mt(i.clip.normal))}) - ${c(i.clip.offset??0)})`:Ge(i),u=c(i.blend??0);a.push(i.op==="sub"?`  ${m}opSub(r, ${d}, ${u});`:`  ${m}opAdd(r, ${d}, ${p}, ${u});`)});let s=St(t,o);return a.push(...e&&s.length?["  if (uReveal.y > 0.5) {",...s.map(i=>`  ${i}`),"  }"]:s),a.push("  r.x *= uScaleFix;","  return r;","}"),a.join(`
`)}function Mt(t){let e=Math.hypot(...t)||1;return[t[0]/e,t[1]/e,t[2]/e]}function Ge(t){switch(t.shape){case"sphere":return`sdSphere(l, ${c(t.radius)})`;case"ellipsoid":return`sdEllipsoid(l, ${S(t.radii)})`;case"roundBox":return`sdRoundBox(l, ${S(t.half)}, ${c(t.round)})`;case"capsule":return`sdCapsule(l, ${S(t.from)}, ${S(t.to)}, ${c(t.radius)})`;case"roundCone":return`sdRoundCone(l, ${S(t.from)}, ${S(t.to)}, ${c(t.r1)}, ${c(t.r2)})`;case"cylinder":return`sdCylinder(l, ${c(t.radius)}, ${c(t.half)}, ${c(t.round)})`;case"frame":return`sdFrame(l, ${H(t.half)}, ${c(t.corner)}, ${c(t.width)}, ${c(t.depth)})`;case"plate":return`sdPlate(l, ${H(t.half)}, ${c(t.corner)}, ${c(t.depth)})`;case"hem":throw new Error("unreachable")}}function St(t,e){let a=t.spec.eyes;if(!a)return[];let r=e(t.boneIndex(a.bone,"eyes")),o=[];if(a.kind==="ball"){let s=c(t.materialId(a.lid,"eyes.lid")),i=a.radius;a.at.forEach((n,l)=>{let h=l===0?"-1.0":"1.0";o.push(`  l = ${r} - ${S(n)};`,`  opAdd(r, length(l) - ${c(i)}, ${c(t.eyeIds[l])}, 0.0);`,"  {",`    float tilt = uFaceB.w * ${h};`,"    vec3 q = vec3(mat2(cos(tilt), sin(tilt), -sin(tilt), cos(tilt)) * l.xy, l.z);",`    float shell = length(q) - ${c(i*1.1)};`,`    float lid = clamp(uFaceA.y + uFaceD.w * ${h} * 0.38 - uFaceD.z * 0.1, 0.0, 1.0);`,`    float top = mix(${c(i*1.18)}, ${c(-i*.14)}, max(uFaceA.x, lid));`,`    float bottom = mix(${c(-i*1.18)}, ${c(-i*.02)}, uFaceA.z * 0.85);`,`    opAdd(r, min(max(shell, top - q.y), max(shell, q.y - bottom)), ${s}, 0.0);`,"  }")})}else{let s=c(t.materialId(a.material,"eyes.material")),[i,n,l]=a.radii;o.push("  float grow = 1.0 + 0.2 * uFaceD.z;"),a.at.forEach((h,f)=>{let p=f===0?"-1.0":"1.0";o.push(`  float open${f} = max(0.12, (1.0 - max(uFaceA.x, clamp(uFaceA.y + uFaceD.w * ${p} * 0.45, 0.0, 1.0))) * (1.0 - 0.6 * uFaceA.z));`,`  l = ${r} - ${S(h)} - vec3(uFaceB.y * ${c(i*.45)}, uFaceB.z * ${c(n*.3)}, 0.0);`,`  opAdd(r, sdEllipsoid(l, vec3(${c(i)} * grow, ${c(n)} * grow * open${f}, ${c(l)})), ${s}, 0.0);`)})}return o}var F=t=>S(O(t));function zt(t,e){let a=t.glows?`uGlow * ${c(t.emitStrength??1)}`:t.emit?`${F(t.emit)} * ${c(t.emitStrength??1)}`:"vec3(0.0)";return`Material(uAlbedo[${e}], ${c(t.f0??.04)}, ${c(t.spec??.5)}, ${c(t.shininess??40)}, ${c(t.metal??0)}, ${c(t.rim??.5)}, ${c(t.sheen??0)}, ${c(t.sss??0)}, ${t.sssColor?F(t.sssColor):"vec3(0.0)"}, ${a}, ${c(t.gloss??.3)})`}var Xe=t=>t.map(e=>`k == ${e}`).join(" || ");function Ke(t,e=!1){let a=["Material getMaterial(float id, vec3 p, vec3 n) {","  int k = int(id + 0.5);","  Material m = material(vec3(0.5));"];return t.materials.forEach(({id:r,spec:o},s)=>a.push(`  ${s?"else ":""}if (k == ${r}) m = ${zt(o,s)};`)),t.spec.paints?.forEach((r,o)=>{let s=t.boneIndex(r.bone,`paints[${o}]`),i=r.on.map(h=>t.materialId(h,`paints[${o}]`)),n=c(r.soft??.15),l=r.kind==="sphere"?`(length(q) - ${c(r.radius??.1)}) / ${c(r.radius??.1)}`:`q.z > 0.0 ? length(q.xy / ${H(r.radii??[.1,.1])}) - 1.0 : 1.0`;a.push(`  if (${Xe(i)}) {`,`    vec3 q = (uBones[${s}] * vec4(p, 1.0)).xyz - ${S(r.at)};`,`    float e = ${l};`,`    m.albedo = mix(m.albedo, ${F(r.color)}, (1.0 - smoothstep(-${n}, ${n}, e)) * ${c(r.opacity??1)}${e?" * uReveal.z":""});`,"  }")}),a.push(...$t(t),...Rt(t,e),"  return m;","}"),a.join(`
`)}function We(t){let e=["void surface(float id, vec3 p, inout vec3 n, inout Material m) {","  int k = int(id + 0.5);"];for(let{id:a,spec:r,name:o}of t.materials){let s=r.surface;if(!s)continue;let i=t.boneIndex(s.bone??"root",`materials.${o}.surface`),n=c(s.strength??.5);e.push(`  if (k == ${a}) {`,`    vec3 q = (uBones[${i}] * vec4(p, 1.0)).xyz * ${c(s.scale)};`,`    float detail = ${n} * (1.0 - smoothstep(0.25, 0.9, gPixel * ${c(s.scale)}));`,...Et(s.kind,s.color),"  }")}return e.push("}"),e.join(`
`)}function Et(t,e){let a=r=>[`    vec3 g = vec3(noise3(${r}), noise3(${r} + 17.3), noise3(${r} + 41.7)) - 0.5;`,"    g -= n * dot(g, n);"];switch(t){case"fur":return[...a("q"),"    n = normalize(n + g * 0.5 * detail);","    float clump = noise3(q * 0.23);","    m.albedo *= mix(1.0, 0.9 + 0.2 * clump, detail);"];case"scales":return["    float c = noise3(q);","    float e = 0.12;","    vec3 grad = vec3(noise3(q + vec3(e, 0, 0)), noise3(q + vec3(0, e, 0)), noise3(q + vec3(0, 0, e))) - c;","    grad -= n * dot(grad, n);","    n = normalize(n - grad * 2.2 * detail);","    float seam = 1.0 - smoothstep(0.03, 0.13, abs(c - 0.5));",`    m.albedo = mix(m.albedo, ${e?F(e):"m.albedo * 0.55"}, seam * 0.7 * detail);`,"    m.albedo *= 0.9 + 0.2 * noise3(q * 0.31) * detail;"];case"speckle":return["    float spot = smoothstep(0.66, 0.7, noise3(q)) * (0.6 + 0.4 * noise3(q * 0.37));",`    m.albedo = mix(m.albedo, ${e?F(e):"m.albedo * 0.6"}, spot * detail);`];case"ripple":return[...a("q"),"    n = normalize(n + g * 0.35 * detail);"]}}function $t(t){let e=t.spec.eyes;if(e?.kind!=="ball")return[];let a=t.boneIndex(e.bone,"eyes"),r=[];return e.at.forEach((o,s)=>{r.push(`  if (k == ${t.eyeIds[s]}) {`,`    vec3 q = normalize((uBones[${a}] * vec4(p, 1.0)).xyz - ${S(o)});`,"    vec3 g = normalize(vec3(uFaceB.y * 0.5, uFaceB.z * 0.38, 1.0));","    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), g));","    vec3 up = cross(g, right);","    vec2 s = vec2(dot(q, right), dot(q, up));","    float front = step(0.0, dot(q, g));",`    float aa = gPixel / ${c(e.radius)} + 0.02;`,"    float rr = length(s);",`    float iris = front - front * smoothstep(${c(e.irisSize)} - aa, ${c(e.irisSize)} + aa, rr);`,`    float ps = ${c(e.pupilSize)} * (1.0 - 0.4 * uFaceD.z);`,`    float pupil = front - front * smoothstep(ps - aa, ps + aa, length(s / vec2(${c(e.pupilAspect??1)}, 1.0)));`,`    vec3 irisCol = ${F(e.iris)} * (0.55 + 0.9 * smoothstep(${c(e.irisSize)}, 0.0, rr)) * (0.7 + 0.3 * hash12(floor(vec2(atan(s.y, s.x) * 9.0, rr * 30.0))));`,"    vec3 albedo = mix(vec3(0.82, 0.8, 0.78), irisCol, iris);","    albedo = mix(albedo, vec3(0.004), pupil);","    m = Material(albedo, 0.06, 2.4, 600.0, 0.0, 0.15, 0.0, 0.0, vec3(0.0), vec3(0.0), 1.0);","  }")}),r}function Rt(t,e){let a=e?" * uReveal.y":"",r=t.spec.face;if(!r)return[];if(r.kind==="screen"){let n=t.boneIndex(r.bone,"face");return[`  if (k == ${t.materialId(r.material,"face.material")}) {`,`    vec2 q = (uBones[${n}] * vec4(p, 1.0)).xy - ${H(r.center)};`,`    m.emit += screenLight(q, ${F(r.color)}, ${c(r.cell)}, ${H(r.half)}, ${c(r.corner)})${a};`,"  }"]}let o=t.boneIndex(r.bone,"face"),s=r.on.map(n=>t.materialId(n,"face.on")),i=r.width;return[`  if (${Xe(s)}) {`,`    vec3 q = (uBones[${o}] * vec4(p, 1.0)).xyz - ${S(r.at)};`,"    if (q.z > -0.02) {",`      vec3 mo = mouth(q.xy, ${c(i)}, uFaceB.x * ${c(i*1.1)}, uFaceD.y, uFaceA.w, uFaceD.w, ${c(i*.12)}, gPixel * 0.8);`,`      float a = mo.x${a};`,`      vec3 inner = ${F(r.color)} * (1.25 - 0.5 * mo.z);`,`      m.albedo = mix(m.albedo, mix(inner, ${F(r.tongue)}, mo.y), a);`,"      m.spec *= 1.0 - 0.6 * a; m.sss *= 1.0 - a; m.sheen *= 1.0 - a; m.emit *= 1.0 - a;","    }","  }"]}var Ye=`
const vec3 KEY = vec3(-0.4485, 0.6997, 0.5562);
const vec3 FILL = vec3(0.8521, -0.1504, 0.5013);
const vec3 BACK = vec3(0.5529, 0.5529, -0.6233);

struct Material {
  vec3 albedo;
  float f0;
  float spec;
  float shininess;
  float metal;
  float rim;
  float sheen;
  float sss;
  vec3 sssColor;
  vec3 emit;
  float gloss;
};

Material material(vec3 albedo) {
  return Material(albedo, 0.04, 0.5, 40.0, 0.0, 0.5, 0.0, 0.0, vec3(0.0), vec3(0.0), 0.3);
}

/* the studio as seen in a reflection along r; gloss tightens the edges of the lights */
vec3 environment(vec3 r, float gloss) {
  float up = r.y;
  float horizon = 0.05 + 0.12 * smoothstep(-0.25, 0.3, up);
  float softbox = 1.1 * smoothstep(mix(0.42, 0.66, gloss), mix(0.78, 0.7, gloss), up) * smoothstep(-0.9, mix(-0.2, -0.75, gloss), r.z - 0.6 * abs(r.x));
  float window = 2.6 * smoothstep(mix(0.86, 0.95, gloss), mix(0.97, 0.965, gloss), dot(r, KEY));
  float strip = 0.5 * smoothstep(0.6, 0.85, -r.x) * smoothstep(-0.35, 0.05, up) * (1.0 - smoothstep(0.2, 0.5, up));
  float floorBounce = 0.06 * smoothstep(0.0, -0.6, up);
  return vec3(0.97, 0.99, 1.04) * (horizon + softbox + window + strip) + vec3(1.0, 0.92, 0.85) * floorBounce;
}

float softShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k) {
  float res = 1.0;
  float t = tmin;
  for (int i = ZERO; i < 32; i++) {
    float h = map(ro + rd * t).x;
    res = min(res, k * h / t);
    t += clamp(h, 0.012, 0.2);
    if (res < 0.002 || t > tmax) break;
  }
  res = clamp(res, 0.0, 1.0);
  return res * res * (3.0 - 2.0 * res);
}

float ambientOcclusion(vec3 p, vec3 n) {
  float occ = 0.0, sca = 1.0;
  for (int i = ZERO; i < 5; i++) {
    float h = 0.012 + 0.12 * float(i) / 4.0;
    occ += (h - map(p + h * n).x) * sca;
    sca *= 0.85;
  }
  return clamp(1.0 - 2.2 * occ, 0.0, 1.0);
}

/* 0 where the body is thick behind the surface, 1 where light gets through */
float thinness(vec3 p, vec3 n) {
  float s = 0.0;
  for (int i = ZERO; i < 3; i++) {
    float h = 0.05 + 0.09 * float(i);
    s += clamp((map(p - n * h).x + h) / h, 0.0, 1.0);
  }
  return s / 3.0;
}

vec3 shade(Material m, vec3 p, vec3 n, vec3 v) {
  vec3 key = KEY;
  float sh = softShadow(p + n * 0.004, key, 0.01, 2.5, 9.0);
  float ao = ambientOcclusion(p, n);

  float ndl = dot(n, key);
  /* a little wrap so the terminator is soft, like a moulded part */
  float keyLight = max(0.0, (ndl + 0.12) / 1.12) * sh;
  float fill = max(0.0, dot(n, FILL));
  float sky = 0.5 + 0.5 * n.y;
  float ndv = max(0.0, dot(n, v));
  float fres = m.f0 + (1.0 - m.f0) * pow(1.0 - ndv, 5.0);
  vec3 r = reflect(-v, n);
  float specOcc = mix(ao, 1.0, 0.35) * mix(sh, 1.0, 0.6);
  vec3 env = environment(r, m.gloss) * fres * specOcc;
  float hi = m.spec * pow(max(0.0, dot(n, normalize(key + v))), m.shininess) * sh;
  float back = max(0.0, dot(n, BACK));
  float rim = m.rim * back * back * pow(1.0 - ndv, 1.6);
  float bounce = 0.1 * max(0.0, -n.y);

  float diffuse = (0.06 + 0.12 * sky) * ao + 1.2 * keyLight + 0.16 * fill * ao + bounce * ao;
  vec3 tint = vec3(1.0 - m.metal) + m.metal * m.albedo * 2.2;
  vec3 col = m.albedo * diffuse * (1.0 - fres * 0.6);
  col += (env + hi) * tint;
  col += rim * vec3(0.62, 0.78, 1.0) * (0.35 + m.albedo);
  /* velvet: fibres catch light at grazing angles */
  col += m.sheen * pow(1.0 - ndv, 2.5) * (0.4 + 0.6 * keyLight) * (m.albedo * 0.7 + 0.3);

  if (m.sss > 0.0) {
    float th = thinness(p, n);
    float through = pow(clamp(dot(v, -key) * 0.5 + 0.5, 0.0, 1.0), 2.0);
    col += m.sssColor * m.sss * (0.18 + 0.55 * th + 0.4 * through * th) * (0.55 + 0.45 * ao);
  }
  return col + m.emit;
}

vec3 aces(vec3 x) {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}
`;var Ze=`
vec3 calcNormal(vec3 p) {
  vec3 n = vec3(0.0);
  for (int i = ZERO; i < 4; i++) {
    vec3 e = 0.5773 * (2.0 * vec3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.0);
    n += e * map(p + 0.0006 * e).x;
  }
  return normalize(n);
}

vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }

void main() {
  vec2 uv = (2.0 * gl_FragCoord.xy - uResolution) / uResolution.y;
  float pitch = uCamera.w;
  vec3 target = vec3(0.0, uCamera.x, 0.0);
  vec3 ro = target + uCamera.y * vec3(0.0, sin(pitch), cos(pitch));
  vec3 fw = normalize(target - ro);
  vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(rt, fw);
  vec3 rd = normalize(fw + (uv.x * rt + uv.y * up) * uCamera.z);
  float pixelAngle = 2.0 * uCamera.z / uResolution.y;

  vec4 body = vec4(0.0);
  float hitT = -1.0;
  vec3 oc = ro - uBound.xyz;
  float b = dot(oc, rd);
  float disc = b * b - dot(oc, oc) + uBound.w * uBound.w;
  if (disc > 0.0) {
    float s = sqrt(disc);
    float t = max(-b - s, 0.0);
    float tEnd = -b + s;
    float nearest = 1e9;
    float nearestT = 0.0;
    for (int i = ZERO; i < 140; i++) {
      float d = map(ro + rd * t).x;
      float px = t * pixelAngle;
      if (d < 0.2 * px) { hitT = t; break; }
      float ratio = d / px;
      if (ratio < nearest) { nearest = ratio; nearestT = t; }
      t += d * 0.85;
      if (t > tEnd) break;
    }
    float coverage = hitT > 0.0 ? 1.0 : 1.0 - smoothstep(0.2, 1.0, nearest);
    if (coverage > 0.0) {
      float tt = hitT > 0.0 ? hitT : nearestT;
      vec3 p = ro + rd * tt;
      gPixel = tt * pixelAngle;
      vec3 n = calcNormal(p);
      float id = map(p).y;
      Material m = getMaterial(id, p, n);
      surface(id, p, n, m);
      vec3 col = pow(aces(shade(m, p, n, -rd) * uExposure), vec3(1.0 / 2.2));
      body = vec4(col * coverage, coverage);
      if (hitT < 0.0) hitT = tt;
    }
  }

  vec4 floorLayer = vec4(0.0);
  if (uFloor > 0.0 && body.a < 1.0 && rd.y < 0.0) {
    vec3 fp = ro + rd * (-ro.y / rd.y);
    float r = length(fp.xz - uBound.xz);
    float reach = uBound.w * 1.15;
    if (r < reach) {
      float sky = softShadow(fp + vec3(0.0, 0.002, 0.0), vec3(0.1191, 0.9800, 0.1588), 0.02, 3.0, 3.2);
      float contact = 1.0 - smoothstep(0.0, 0.28, map(fp).x);
      float dark = (1.0 - sky) * 0.4 + contact * contact * 0.32;
      dark *= 1.0 - smoothstep(reach * 0.45, reach, r);
      /* a shadow fades as what casts it rises */
      dark *= mix(1.0, 0.5, smoothstep(0.0, 0.45, uLift));
      /* the state's light pooling on the floor */
      vec3 pool = uGlow * uGlowPool * exp(-r * r * 5.0) * (1.0 - dark);
      floorLayer = vec4(uShadow * dark + pool, dark) * uFloor;
    }
  }

  vec4 front = vec4(0.0);
  vec4 back = vec4(0.0);
  float pixel = 2.0 / uResolution.y;
  for (int i = 0; i < uFxCount; i++) {
    vec4 A = uFxA[i];
    vec4 B = uFxB[i];
    vec3 d = A.xyz - ro;
    float z = dot(d, fw);
    if (z < 0.1) continue;
    float scale = 1.0 / (z * uCamera.z);
    vec2 q = (uv - vec2(dot(d, rt), dot(d, up)) * scale) / (A.w * scale);
    if (dot(q, q) > 2.0) continue;
    float cr = cos(B.z), sr = sin(B.z);
    q = mat2(cr, -sr, sr, cr) * q;
    vec2 g = glyph(int(B.x + 0.5), q, pixel / (A.w * scale));
    float a = g.x * B.y;
    if (a < 0.002) continue;
    vec3 col = mix(uFxC[i].rgb, vec3(1.0), clamp(g.y, 0.0, 1.0)) * (1.0 + min(g.y, 0.0));
    vec4 layer = B.w > 0.5 ? vec4(col * a, 0.0) : vec4(col * a, a);
    if (hitT > 0.0 && hitT < length(d)) back = over(layer, back);
    else front = over(layer, front);
  }

  fragColor = over(front, over(body, over(back, floorLayer)));
}
`;var Qe=`
/* q: point in mouth space (x right, y up); w: half width; open: lip
   separation in the same units; round: 0 for "ah"/"ee", 1 for "oo";
   smile: -1..1; crooked: -1..1 tilts and wobbles the line, as when something
   is wrong; t: half the stroke; px: a pixel in mouth units.
   Returns coverage, tongue coverage, and depth inside the mouth (0 at the lips, 1 deep). */
vec3 mouth(vec2 q, float w, float open, float round, float smile, float crooked, float t, float px) {
  float opened = smoothstep(0.0, 0.25 * w, open);
  w *= 1.0 - 0.3 * round * opened;
  open *= 1.0 + 0.1 * round;
  /* an "oo" pushes the lips forward and flattens the smile out of them */
  float bend = smile * 0.55 * (1.0 - 0.7 * round * opened);

  float u = clamp(q.x / w, -1.0, 1.0);
  float bulge = sqrt(max(1.0 - u * u, 0.0));
  float line = bend * w * u * u + crooked * w * (0.22 * u + 0.12 * sin(u * 6.0));
  float upper = line + open * (0.22 + 0.45 * round) * bulge;
  float lower = line - open * bulge;

  /* vertical distances are cheap and exact along y; the slope converts the
     antialiasing width so the steep sides near the corners stay crisp */
  float steep = abs(u) / max(bulge, 0.08);
  float slope = abs(2.0 * bend * u) + abs(crooked) * 0.9 + open / w * steep;
  float aa = px * sqrt(1.0 + min(slope * slope, 36.0));

  /* the lips taper toward the corners once the mouth is open */
  float lip = t * mix(1.0, sqrt(bulge), opened);
  float inside = max(q.y - upper, lower - q.y);
  float body = abs(q.x) <= w ? inside - lip : 1e3;
  /* round caps finish the closed stroke; an open mouth's lips already meet in a point */
  float cap = length(vec2(abs(q.x) - w, q.y - bend * w - crooked * w * (0.22 * sign(q.x) + 0.12 * sin(6.0 * sign(q.x))))) - t;
  float a = max(1.0 - smoothstep(-aa, aa, body), (1.0 - smoothstep(-px, px, cap)) * (1.0 - opened));

  /* a tongue resting on the lower lip, only inside the opening */
  float hole = 1.0 - smoothstep(-aa, aa, inside);
  vec2 tq = vec2(q.x / (w * (0.5 - 0.1 * round)), (q.y + open * 0.78) / max(0.42 * open, 1e-4));
  float tongue = (1.0 - smoothstep(-0.08, 0.08, length(tq) - 1.0)) * hole * smoothstep(0.08, 0.35, open / w);

  float depth = clamp(-inside / max(0.5 * open, 1e-4), 0.0, 1.0) * hole;
  return vec3(a, tongue, depth);
}
`;var Je=`
float fxSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

float fxDot2(vec2 v) { return dot(v, v); }

float fxHeart(vec2 p) {
  p.x = abs(p.x);
  if (p.y + p.x > 1.0) return sqrt(fxDot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
  return sqrt(min(fxDot2(p - vec2(0.0, 1.0)), fxDot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float fxTeardrop(vec2 p, float r1, float r2, float h) {
  p.x = abs(p.x);
  float b = (r1 - r2) / h;
  float a = sqrt(1.0 - b * b);
  float k = dot(p, vec2(-b, a));
  if (k < 0.0) return length(p) - r1;
  if (k > a * h) return length(p - vec2(0.0, h)) - r2;
  return dot(p, vec2(a, b)) - r1;
}

float fxStar(vec2 p, float r, float rf) {
  const vec2 k1 = vec2(0.809016994375, -0.587785252292);
  const vec2 k2 = vec2(-k1.x, k1.y);
  p.x = abs(p.x);
  p -= 2.0 * max(dot(k1, p), 0.0) * k1;
  p -= 2.0 * max(dot(k2, p), 0.0) * k2;
  p.x = abs(p.x);
  p.y -= r;
  vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
  float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
  return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float fxTriangle(vec2 p, float r) {
  const float k = 1.7320508;
  p.x = abs(p.x) - r;
  p.y = p.y + r / k;
  if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
  p.x -= clamp(p.x, -2.0 * r, 0.0);
  return -length(p) * sign(p.y);
}

/* an exclamation mark, tapering toward its dot */
float fxExclaim(vec2 p) {
  float bar = fxSegment(p, vec2(0.0, -0.2), vec2(0.0, 0.8)) - mix(0.11, 0.19, clamp((p.y + 0.2), 0.0, 1.0));
  return min(bar, length(p - vec2(0.0, -0.66)) - 0.15);
}

/* coverage, highlight */
vec2 glyph(int g, vec2 p, float px) {
  float d = 1e9;
  float light = 0.0;
  float soft = 0.0;
  if (g == 0) {
    d = min(min(fxSegment(p, vec2(-0.6, 0.6), vec2(0.6, 0.6)), fxSegment(p, vec2(0.6, 0.6), vec2(-0.6, -0.6))), fxSegment(p, vec2(-0.6, -0.6), vec2(0.6, -0.6))) - 0.16;
  } else if (g == 1) {
    float ring = abs(length(p) - 0.82) - 0.07;
    float shine = length(p - vec2(-0.32, 0.36)) - 0.17;
    d = min(ring, shine);
    light = 1.0 - smoothstep(-px, px, shine);
    soft = 0.14 * (1.0 - smoothstep(0.75, 0.82, length(p)));
  } else if (g == 2) {
    vec2 q = abs(p);
    d = (sqrt(q.x) + sqrt(q.y) - 0.92) * 0.45;
    light = 1.0 - smoothstep(0.0, 0.35, length(p));
  } else if (g == 3) {
    d = fxHeart(p * 0.56 + vec2(0.0, 0.5)) / 0.56;
    light = (1.0 - smoothstep(-px, px, length(p - vec2(-0.38, 0.38)) - 0.13)) * 0.8;
  } else if (g == 4) {
    vec2 h = p - vec2(-0.28, -0.55);
    float head = (length(mat2(0.92, 0.39, -0.39, 0.92) * h / vec2(0.32, 0.23)) - 1.0) * 0.23;
    float stem = fxSegment(p, vec2(0.02, -0.5), vec2(0.02, 0.78)) - 0.07;
    float flag = fxSegment(p, vec2(0.02, 0.78), vec2(0.42, 0.36)) - 0.09;
    d = min(head, min(stem, flag));
  } else if (g == 5) {
    vec2 c = p - vec2(-1.1, 0.0);
    float a = atan(c.y, c.x);
    d = max(abs(length(c) - 1.45) - 0.1, (abs(a) - 0.48) * 1.45);
  } else if (g == 6) {
    float r = length(p);
    return vec2((1.0 - smoothstep(0.15, 1.0, r)) * 0.75, 0.25 + 0.35 * p.y);
  } else if (g == 7) {
    d = abs(length(p) - 0.84) - 0.06;
  } else if (g == 8) {
    d = fxTeardrop(p + vec2(0.0, 0.35), 0.55, 0.06, 1.05);
    light = (1.0 - smoothstep(-px, px, length(p - vec2(-0.2, -0.2)) - 0.12)) * 0.9;
  } else if (g == 9) {
    d = fxSegment(p, vec2(-1.0, 0.0), vec2(1.0, 0.0)) - 0.12 * (1.0 - abs(p.x) * 0.7);
    light = 0.6;
  } else if (g == 10) {
    float r = length(p);
    return vec2(exp(-r * r * 5.0), 1.0 - smoothstep(0.0, 0.3, r));
  } else if (g == 11) {
    d = (length(p / vec2(0.3, 0.95)) - 1.0) * 0.3;
    light = -0.35 * (1.0 - smoothstep(0.0, 0.05 + px, abs(p.x + 0.04 * p.y)));
  } else if (g == 13) {
    d = fxExclaim(p);
    light = 0.3 * (1.0 - smoothstep(-px, px, fxSegment(p, vec2(-0.05, 0.1), vec2(-0.05, 0.7)) - 0.035));
  } else if (g == 14) {
    d = fxTriangle(p - vec2(0.0, -0.12), 0.82) - 0.14;
    /* a white mark on the coloured sign */
    light = 1.0 - smoothstep(-px, px, fxExclaim((p - vec2(0.0, -0.08)) / 0.52) * 0.52);
  } else if (g == 15) {
    vec2 q = abs(p) - vec2(0.32, 0.78);
    d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.06;
    light = 0.35 * step(0.0, p.x);
  } else if (g == 16) {
    float c = min(min(length(p - vec2(-0.48, -0.08)) - 0.4, length(p - vec2(0.08, 0.18)) - 0.55), length(p - vec2(0.56, -0.1)) - 0.36);
    d = max(c, -p.y - 0.44);
    light = 0.45 * smoothstep(-0.2, 0.7, p.y) - 0.25 * (1.0 - smoothstep(-0.45, -0.1, p.y));
  } else if (g == 17) {
    d = fxStar(p, 0.92, 0.46) - 0.06;
    light = 0.5 * (1.0 - smoothstep(0.0, 0.45, length(p - vec2(-0.12, 0.18))));
  } else if (g == 18) {
    float r = length(p);
    float teeth = 0.66 + 0.2 * smoothstep(-0.25, 0.25, cos(atan(p.y, p.x) * 8.0));
    d = max(r - teeth, 0.26 - r);
    light = 0.3 * (1.0 - smoothstep(0.3, 0.7, length(p - vec2(-0.2, 0.25))));
  } else {
    d = length(p) - 0.9;
    light = 0.35 * (1.0 - smoothstep(0.0, 0.6, length(p - vec2(-0.3, 0.35))));
  }
  return vec2(max(1.0 - smoothstep(-px, px, d), soft), light);
}
`;var et=`
float sdSphere(vec3 p, float r) { return length(p) - r; }

float sdEllipsoid(vec3 p, vec3 r) {
  float k0 = length(p / r);
  float k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / max(k1, 1e-6);
}

float sdRoundBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
  vec3 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
  vec3 ba = b - a;
  float l2 = dot(ba, ba);
  float rr = r1 - r2;
  float a2 = l2 - rr * rr;
  float il2 = 1.0 / l2;
  vec3 pa = p - a;
  float y = dot(pa, ba);
  float z = y - l2;
  vec3 xv = pa * l2 - ba * y;
  float x2 = dot(xv, xv);
  float y2 = y * y * l2;
  float z2 = z * z * l2;
  float k = sign(rr) * rr * rr * x2;
  if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
  if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
  return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

/* along y, with rounded rims */
float sdCylinder(vec3 p, float r, float h, float rr) {
  vec2 d = vec2(length(p.xz) - r + rr, abs(p.y) - h + rr);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rr;
}

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/* a rounded-rectangle ring in the xy plane, extruded along z: gaskets, bezels */
float sdFrame(vec3 p, vec2 b, float corner, float w, float depth) {
  float ring = abs(sdRoundRect(p.xy, b, corner)) - w;
  vec2 e = vec2(ring, abs(p.z) - depth);
  return min(max(e.x, e.y), 0.0) + length(max(e, 0.0));
}

float sdPlate(vec3 p, vec2 b, float corner, float depth) {
  vec2 e = vec2(sdRoundRect(p.xy, b, corner), abs(p.z) - depth);
  return min(max(e.x, e.y), 0.0) + length(max(e, 0.0));
}

float smin(float a, float b, float k) {
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

float smax(float a, float b, float k) { return -smin(-a, -b, k); }

/* union that keeps the material of whichever surface is nearer */
void opAdd(inout vec2 r, float d, float id, float k) {
  float m = d < r.x ? id : r.y;
  r.x = k > 0.0 ? smin(r.x, d, k) : min(r.x, d);
  r.y = m;
}

void opSub(inout vec2 r, float d, float k) {
  r.x = k > 0.0 ? smax(r.x, -d, k) : max(r.x, -d);
}

float hash13(vec3 p3) {
  p3 = fract(p3 * 0.1031);
  p3 += dot(p3, p3.zyx + 31.32);
  return fract((p3.x + p3.y) * p3.z);
}

/* smooth value noise, 0\u20131 */
float noise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
    mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
    f.z);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
`;var tt=`
float sdBox2(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float fxStarLed(vec2 p, float r, float rf) {
  const vec2 k1 = vec2(0.809016994375, -0.587785252292);
  const vec2 k2 = vec2(-k1.x, k1.y);
  p.x = abs(p.x);
  p -= 2.0 * max(dot(k1, p), 0.0) * k1;
  p -= 2.0 * max(dot(k2, p), 0.0) * k2;
  p.x = abs(p.x);
  p.y -= r;
  vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
  float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
  return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

/* how lit a shape is at distance d: 1 inside, falling off over soft */
float lit(float d, float soft) { return 1.0 - smoothstep(-0.35, soft, d); }

float faceEyes(vec2 c, float soft) {
  vec2 g = vec2(uFaceB.y * 2.2, uFaceB.z * 1.4);
  float blink = uFaceA.x;
  float v = 0.0;
  for (int i = 0; i < 2; i++) {
    float side = i == 0 ? -1.0 : 1.0;
    float lid = clamp(uFaceA.y + uFaceD.w * side * 0.4, 0.0, 1.0);
    float closeTop = max(blink * 0.48, lid * 0.42);
    float closeBottom = max(blink * 0.48, uFaceA.z * 0.4);
    float cx = side * 4.5 + g.x;
    float top = 3.5 + 0.8 * uFaceD.z + g.y - 4.0 * closeTop;
    float bottom = -0.5 - 0.5 * uFaceD.z + g.y + 4.0 * closeBottom;
    float h = max((top - bottom) * 0.5, 0.32);
    float d = sdBox2(c - vec2(cx, (top + bottom) * 0.5), vec2(1.5 + 0.3 * uFaceD.z, h)) - 0.15;
    v = max(v, lit(d, soft));
  }
  return v;
}

/* a mouth of two lips, like the painted ones: open is in LED rows */
float faceMouth(vec2 c, float open, float round, float smile, float soft) {
  float opened = smoothstep(0.0, 0.8, open);
  float w = 3.4 - 1.4 * round * opened;
  vec2 m = c - vec2(0.0, -3.7 + 0.25 * open);
  float u = clamp(m.x / w, -1.0, 1.0);
  float bulge = sqrt(max(1.0 - u * u, 0.0));
  float line = smile * 0.9 * u * u;
  float inside = max(m.y - line - open * (0.2 + 0.45 * round) * bulge, line - open * bulge - m.y);
  float body = abs(m.x) <= w ? inside : 1e3;
  float rim = min(abs(body), length(vec2(abs(m.x) - w, m.y - smile * 0.9))) - 0.42;
  return max(lit(rim, soft), lit(body, soft) * 0.12 * opened);
}

float faceZ(vec2 c, vec2 at, float s, float soft) {
  vec2 p = (c - at) / s;
  float d = min(min(sdSegment(p, vec2(-1, 1), vec2(1, 1)), sdSegment(p, vec2(1, 1), vec2(-1, -1))), sdSegment(p, vec2(-1, -1), vec2(1, -1)));
  return lit(d * s - 0.32, soft);
}

bool is(float state, float id) { return abs(state - id) < 0.5; }

float faceFor(float state, vec2 c, float t, float soft) {
  float v = 0.0;
  if (is(state, E_THINKING)) {
    /* heavy-lidded eyes looking up, three dots pulsing in turn */
    v = faceEyes(c, soft);
    for (int i = 0; i < 3; i++) {
      float fi = float(i);
      float pulse = 0.5 + 0.5 * sin(t * 4.2 - fi * 1.1);
      float d = length(c - vec2(-2.4 + fi * 2.4, -4.4)) - 0.62;
      v = max(v, lit(d, soft) * (0.25 + 0.75 * pulse * pulse));
    }
  } else if (is(state, E_LISTENING)) {
    /* alert eyes over a live equaliser */
    v = faceEyes(c, soft);
    for (int i = 0; i < 7; i++) {
      float fi = float(i);
      float level = abs(sin(t * (5.0 + fi * 1.3) + fi * 1.7)) * (0.55 + 0.45 * sin(t * 2.3 + fi));
      float d = sdBox2(c - vec2(-4.5 + fi * 1.5, -4.6), vec2(0.42, 0.45 + 1.6 * level));
      v = max(v, lit(d, soft) * 0.9);
    }
  } else if (is(state, E_SPEAKING)) {
    /* the same two-lip mouth as the painted faces; closed, the lips meet in one bar */
    v = max(faceEyes(c, soft), faceMouth(c, uFaceB.x * 3.4, uFaceD.y, 0.0, soft));
  } else if (is(state, E_SLEEPING)) {
    /* closed eyes and rising z's */
    for (int i = 0; i < 2; i++) {
      float cx = i == 0 ? -4.5 : 4.5;
      float d = min(sdSegment(c, vec2(cx - 1.6, 1.4), vec2(cx, 0.6)), sdSegment(c, vec2(cx, 0.6), vec2(cx + 1.6, 1.4))) - 0.38;
      v = max(v, lit(d, soft));
    }
    for (int i = 0; i < 3; i++) {
      float k = fract(t * 0.22 + float(i) / 3.0);
      float fade = smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.7, 1.0, k));
      v = max(v, faceZ(c, vec2(7.6 + k * 3.2, 1.2 + k * 5.0), 0.5 + k * 0.55, soft) * fade);
    }
  } else if (is(state, E_WORKING)) {
    /* narrowed eyes over a progress bar that fills, empties and fills again */
    v = faceEyes(c, soft);
    float rim = abs(sdBox2(c - vec2(0.0, -4.6), vec2(4.6, 0.95))) - 0.3;
    float fill = fract(t * 0.3) * 8.4;
    float bar = sdBox2(c - vec2(-4.2 + fill * 0.5, -4.6), vec2(fill * 0.5, 0.35));
    v = max(v, max(lit(rim, soft) * 0.55, lit(bar, soft)));
  } else if (is(state, E_ERROR)) {
    /* X eyes and a zigzag mouth */
    for (int i = 0; i < 2; i++) {
      vec2 e = c - vec2(i == 0 ? -4.5 : 4.5, 1.5);
      float d = min(sdSegment(e, vec2(-1.5, -1.5), vec2(1.5, 1.5)), sdSegment(e, vec2(-1.5, 1.5), vec2(1.5, -1.5))) - 0.42;
      v = max(v, lit(d, soft));
    }
    float zig = 1e3;
    for (int i = 0; i < 4; i++) {
      float x0 = -3.6 + float(i) * 1.8;
      zig = min(zig, sdSegment(c, vec2(x0, -4.6 + (i % 2 == 0 ? 0.6 : -0.6)), vec2(x0 + 1.8, -4.6 + (i % 2 == 0 ? -0.6 : 0.6))));
    }
    v = max(v, lit(zig - 0.4, soft));
  } else if (is(state, E_SURPRISED)) {
    /* round eyes with pinned pupils, and a little "o" */
    for (int i = 0; i < 2; i++) {
      vec2 e = c - vec2(i == 0 ? -4.5 : 4.5, 1.4);
      float ring = abs(length(e) - 2.0) - 0.42;
      v = max(v, max(lit(ring, soft), lit(length(e) - 0.62, soft)));
    }
    v = max(v, lit(abs(length(c - vec2(0.0, -4.7)) - 1.05) - 0.4, soft));
  } else if (is(state, E_CELEBRATING)) {
    /* star eyes that throb, and a wide open grin */
    float throb = 1.0 + 0.12 * sin(t * 9.0);
    for (int i = 0; i < 2; i++) {
      vec2 e = (c - vec2(i == 0 ? -4.5 : 4.5, 1.6)) / throb;
      v = max(v, lit(fxStarLed(e, 2.2, 0.48) * throb - 0.1, soft));
    }
    v = max(v, faceMouth(c - vec2(0.0, 0.6), 2.6, 0.0, 0.7, soft));
  } else if (is(state, E_SAD)) {
    /* eyes cut away at the outer top, a frown, and a tear now and then */
    for (int i = 0; i < 2; i++) {
      float side = i == 0 ? -1.0 : 1.0;
      float cx = side * 4.5;
      float box = sdBox2(c - vec2(cx, 1.0), vec2(1.5, 1.6)) - 0.15;
      float slope = (c.y - 1.9) + 0.55 * (c.x - cx) * side;
      v = max(v, lit(max(box, slope), soft));
    }
    float frown = max(abs(length(c - vec2(0.0, -7.2)) - 2.6) - 0.4, -(c.y + 5.4));
    v = max(v, lit(frown, soft));
    float k = fract(t * 0.35);
    float tear = length((c - vec2(-5.4, -0.6 - k * 5.0)) / vec2(0.8, 1.0)) - 0.6;
    v = max(v, lit(tear, soft) * smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.6, 0.9, k)));
  } else if (is(state, E_HAPPY)) {
    /* ^ ^ and a smile */
    for (int i = 0; i < 2; i++) {
      float cx = i == 0 ? -4.5 : 4.5;
      float d = min(sdSegment(c, vec2(cx - 1.7, 0.4), vec2(cx, 2.2)), sdSegment(c, vec2(cx, 2.2), vec2(cx + 1.7, 0.4))) - 0.5;
      v = max(v, lit(d, soft));
    }
    float d = min(min(sdSegment(c, vec2(-3.0, -3.0), vec2(-1.3, -4.6)), sdSegment(c, vec2(-1.3, -4.6), vec2(1.3, -4.6))), sdSegment(c, vec2(1.3, -4.6), vec2(3.0, -3.0))) - 0.45;
    v = max(v, lit(d, soft));
  } else {
    v = faceEyes(c, soft);
  }
  return v;
}

/* the face at c, cross-faded from the previous state and glitched on a switch */
float face(vec2 c, float soft) {
  float row = floor(c.y);
  float tick = floor(uTime * 24.0);
  /* an error keeps glitching now and then */
  float glitch = max(uFaceC.w, is(uFaceC.x, E_ERROR) ? 0.6 * step(0.86, hash12(vec2(floor(uTime * 8.0), 7.7))) : 0.0);
  c.x += (hash12(vec2(row, tick)) - 0.5) * 7.0 * glitch * step(0.6, hash12(vec2(row * 1.7, tick)));
  float now = faceFor(uFaceC.x, c, uFaceD.x, soft);
  float before = faceFor(uFaceC.y, c, uFaceD.x, soft);
  float v = mix(before, now, uFaceC.z);
  return v * (1.0 - glitch * 0.45 * hash12(vec2(tick, 3.1)));
}

/* the emitted light of the matrix at a point on the screen (screen-local, in units) */
vec3 screenLight(vec2 q, vec3 color, float cell, vec2 extent, float corner) {
  vec2 c = q / cell;
  vec2 cellCentre = floor(c) + 0.5;
  vec2 f = fract(c) - 0.5;
  /* round LEDs, averaged out when one is smaller than a couple of pixels */
  float dotMask = 1.0 - smoothstep(0.26, 0.4, length(f));
  float footprint = gPixel / cell;
  dotMask = mix(dotMask, 0.5, smoothstep(0.18, 0.45, footprint));
  float led = face(cellCentre, 0.25);
  float glow = face(c, 1.6);
  float edge = smoothstep(0.0, 0.05, -sdRoundRect(q, extent, corner));
  /* a faint glare across the glass */
  float glare = 0.025 * smoothstep(0.1, 0.0, abs(q.x * 0.7 + q.y - extent.y * 0.35));
  vec3 lit = color * (led * dotMask * 2.1 + glow * 0.2) + glare + vec3(0.012, 0.016, 0.03) * dotMask;
  return lit * edge;
}
`;var we=class extends Error{constructor(e,a){super(`${e}: ${a}`),this.name="SpecError"}};function at(t){let e=p=>{throw new we(t.id,p)},a=[{name:"root",pivot:[0,0,0],index:0,parentIndex:-1}],r=new Map([["root",0]]);t.bones.forEach((p,m)=>{r.has(p.name)&&e(`bone "${p.name}" is declared twice`);let d=p.parent??"root",u=r.get(d);u===void 0&&e(`bone "${p.name}" names parent "${d}", which is not declared before it`),r.set(p.name,m+1),a.push({...p,index:m+1,parentIndex:u})});let o=Object.entries(t.materials).map(([p,m],d)=>({name:p,id:d+1,spec:m})),s=new Map(o.map(p=>[p.name,p.id])),i=[o.length+1,o.length+2],n=(p,m)=>r.get(p)??e(`${m} names bone "${p}", which does not exist`),l=(p,m)=>s.get(p)??e(`${m} names material "${p}", which does not exist`);o.forEach(p=>{p.spec.shadeOf!==void 0&&l(p.spec.shadeOf,`materials.${p.name}.shadeOf`)}),t.parts.forEach((p,m)=>{n(p.bone,`parts[${m}]`),l(p.material,`parts[${m}]`)}),t.paints?.forEach((p,m)=>{n(p.bone,`paints[${m}]`),p.on.forEach(d=>l(d,`paints[${m}]`))});let h=a.map(()=>[]);for(let[p,m]of Object.entries(t.acting??{}))for(let[d,u]of Object.entries(m)){let y=n(d,`acting.${p}`);for(let[w,b]of Object.entries(u))h[y].push([p,w,b])}let f={};for(let[p,m]of Object.entries(t.anchors??{}))f[p]={bone:n(m.bone,`anchors.${p}`),at:m.at};for(let[p,m]of Object.entries(t.fx??{}))p!=="replace"&&m.forEach((d,u)=>{f[d.anchor]||e(`fx.${p}[${u}] names anchor "${d.anchor}", which does not exist`)});return{spec:t,bones:a,boneIndex:n,materials:o,materialId:l,eyeIds:i,acting:h,anchors:f}}var le={uResolution:"vec2",uTime:"float",uCamera:"vec4",uBound:"vec4",uBones:"mat4[]",uScaleFix:"float",uFaceA:"vec4",uFaceB:"vec4",uFaceC:"vec4",uFaceD:"vec4",uGlow:"vec3",uShadow:"vec3",uFloor:"float",uLift:"float",uGlowPool:"float",uExposure:"float",uAlbedo:"vec3[materials]",uFxA:"vec4[fx]",uFxB:"vec4[fx]",uFxC:"vec4[fx]",uFxCount:"int",uReveal:"vec3"};function rt(t,e){return Object.entries(le).map(([a,r])=>r==="mat4[]"?`uniform mat4 ${a}[${t}];`:r==="vec3[materials]"?`uniform vec3 ${a}[${Math.max(1,e)}];`:r==="vec4[fx]"?`uniform vec4 ${a}[${K}];`:`uniform ${r} ${a};`).join(`
`)}var ot=`#version 300 es
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`,Ct=()=>A.map(t=>`#define E_${t.toUpperCase()} ${c(Q[t])}`).join(`
`)+`
`;function st(t,e={}){let a=at(t),r=e.reveal??!1,o=["#version 300 es","precision highp float;","precision highp int;",rt(a.bones.length,a.materials.length),"out vec4 fragColor;","float gPixel = 0.001;","#define ZERO (min(int(uTime), 0))",et,Ue(a,r),Ye,t.face?.kind==="screen"?Ct()+tt:"",t.face?.kind==="mouth"?Qe:"",Ke(a,r),We(a),Je,Ze].join(`
`);return{spec:t,bones:a.bones,acting:a.acting,anchors:a.anchors,fragment:o,materials:a.materials.map(s=>s.name),albedo:new Float32Array(a.materials.flatMap(s=>O(s.spec.color))),stats:{parts:t.parts.length+(t.eyes?2:0),bones:a.bones.length,materials:a.materials.length,shaderLines:o.split(`
`).length},reveal:r}}var At=48,ce=128,Ft=null,W=class t{static shared(){return Ft??=new t}canvas=document.createElement("canvas");gl;programs=new Map;parallel;lastSyncBuild=1/0;constructor(){let e=this.canvas.getContext("webgl2",{alpha:!0,premultipliedAlpha:!0,antialias:!1,depth:!1,stencil:!1,powerPreference:"high-performance"});if(!e)throw new Error("WebGL2 is not available");this.gl=e,this.parallel=e.getExtension("KHR_parallel_shader_compile"),this.parallel||requestAnimationFrame(()=>setTimeout(()=>this.lastSyncBuild=-1/0)),e.enable(e.SCISSOR_TEST),e.clearColor(0,0,0,0),this.canvas.addEventListener("webglcontextlost",a=>a.preventDefault()),this.canvas.addEventListener("webglcontextrestored",()=>{this.programs.clear(),e.enable(e.SCISSOR_TEST),e.clearColor(0,0,0,0)})}program(e){let a=this.programs.get(e);if(a==="failed")return null;if(a&&"program"in a)return a;if(!a){if(!this.parallel){let o=performance.now();if(o-this.lastSyncBuild<At)return null;this.lastSyncBuild=o}let r=this.start(e);return this.programs.set(e,r),this.parallel?null:this.finish(e,r)}return this.parallel&&!this.gl.getProgramParameter(a.building,this.parallel.COMPLETION_STATUS_KHR)?null:this.finish(e,a)}reserve(e,a){let r=Math.ceil(e/ce)*ce,o=Math.ceil(a/ce)*ce;r>this.canvas.width&&(this.canvas.width=r),o>this.canvas.height&&(this.canvas.height=o)}start(e){let{gl:a}=this,r=(n,l)=>{let h=a.createShader(n);return a.shaderSource(h,l),a.compileShader(h),h},o=r(a.VERTEX_SHADER,ot),s=r(a.FRAGMENT_SHADER,e.fragment),i=a.createProgram();return a.attachShader(i,o),a.attachShader(i,s),a.linkProgram(i),{building:i,vertex:o,fragment:s}}finish(e,{building:a,vertex:r,fragment:o}){let{gl:s}=this;if(!s.getProgramParameter(a,s.LINK_STATUS)){let l=s.getShaderInfoLog(o)||s.getProgramInfoLog(a);throw this.programs.set(e,"failed"),new Error(`${e.spec.id}: shader failed to build
${l}`)}s.deleteShader(r),s.deleteShader(o);let i=Object.fromEntries(Object.keys(le).map(l=>[l,s.getUniformLocation(a,le[l].includes("[")?`${l}[0]`:l)])),n={program:a,uniforms:i,character:e};return this.programs.set(e,n),n}};var ke=(t,e)=>[t[0]+e[0],t[1]+e[1],t[2]+e[2]],Me=(t,e)=>[t[0]-e[0],t[1]-e[1],t[2]-e[2]],pe=(t,e)=>[t[0]*e,t[1]*e,t[2]*e],it=(t,e)=>t[0]*e[0]+t[1]*e[1]+t[2]*e[2],nt=(t,e)=>[t[1]*e[2]-t[2]*e[1],t[2]*e[0]-t[0]*e[2],t[0]*e[1]-t[1]*e[0]],Se=t=>Math.hypot(t[0],t[1],t[2]);function J(t){let e=Se(t)||1;return[t[0]/e,t[1]/e,t[2]/e]}var lt=["rx","ry","rz"];function qt(t,e){if(typeof t=="number")return t;let[a,r=0,o=0,s=0]=t;return a+r*Math.sin(e*o*Math.PI*2+s)}var he=class{constructor(e,a=e.map(()=>[])){this.bones=e;this.acting=a;this.world=e.map(()=>$()),this.inverse=new Float32Array(e.length*16),this.tips=e.map(()=>null),this.spun=e.map(()=>({rx:0,ry:0,rz:0}))}world;inverse;tips;spun;scratch={t:$(),r:$(),j:$(),inv:$()};point(e,a){return ve(this.world[e],a)}update(e,a,r,o,s){let{t:i,r:n,j:l,inv:h}=this.scratch;this.world[0].set(e);for(let f=1;f<this.bones.length;f++){let p=this.bones[f],m={rx:p.rest?.rx??0,ry:p.rest?.ry??0,rz:p.rest?.rz??0};for(let u of lt){for(let[w,b]of p.drive?.[u]??[])m[u]+=a[w]*b;let y=p.wave?.[u];y&&(m[u]+=y[0]*a.energy*Math.sin(o*y[1]*Math.PI*2+y[2]))}for(let[u,y,w]of this.acting[f]){let b=r[u];b<.001&&!(Array.isArray(w)&&w[4])||(m[y]+=b*qt(w,o),Array.isArray(w)&&w[4]&&(this.spun[f][y]+=b*w[4]*s))}for(let u of lt)m[u]+=this.spun[f][u];let d=this.world[f];N(d,this.world[p.parentIndex],ee(i,...p.pivot)),N(d,d,X(n,m.rx,m.ry,m.rz)),p.jiggle&&N(d,d,this.jiggle(f,d,s,l,h))}for(let f=0;f<this.bones.length;f++)this.inverse.set(ge(h,this.world[f]),f*16)}jiggle(e,a,r,o,s){let{axis:i,length:n,freq:l,damping:h,maxAngle:f=.9}=this.bones[e].jiggle,p=ve(a,[0,0,0]),m=ke(p,pe(J(be(a,i)),n)),d=this.tips[e];if((!d||!(r>0))&&(d=this.tips[e]=d??{x:m,v:[0,0,0]},!(r>0)))return te(o,[0,1,0],0);let u=l*Math.PI*2;for(let M=0;M<3;M++)d.v[M]+=(u*u*(m[M]-d.x[M])-2*h*u*d.v[M])*r,d.x[M]+=d.v[M]*r;d.x=ke(p,pe(J(Me(d.x,p)),n)),ge(s,a);let y=J(be(s,Me(d.x,p))),w=J(i),b=nt(w,y),z=Se(b);if(z<1e-6)return te(o,[0,1,0],0);let R=E(Math.atan2(z,it(w,y)),0,f);return te(o,pe(b,1/z),R)}};var ct=.2,Lt=.1,It=[1e6,1,1],fe=class{constructor(e){this.canvas=e;let a=e.getContext("2d");if(!a)throw new Error("Canvas 2D is not available");this.target=a}gpu=W.shared();target;character=null;load(e){this.character=e,this.gpu.program(e)}render(e){let a=this.character&&this.gpu.program(this.character);if(!a)return!1;let{gpu:r}=this,{gl:o}=r,{width:s,height:i}=e;(this.canvas.width!==s||this.canvas.height!==i)&&(this.canvas.width=s,this.canvas.height=i),r.reserve(s,i),o.viewport(0,0,s,i),o.scissor(0,0,s,i),o.clear(o.COLOR_BUFFER_BIT),o.useProgram(a.program);let n=a.uniforms,{spec:l}=a.character,h=e.pose,f=h.lift;return o.uniform2f(n.uResolution,e.width,e.height),o.uniform1f(n.uTime,e.time),o.uniform4f(n.uCamera,l.frame.target,l.frame.radius*e.framing/ct,ct,Lt),o.uniform4f(n.uBound,0,l.bound.y+f,0,l.bound.radius),o.uniformMatrix4fv(n.uBones,!1,e.bones),o.uniform1f(n.uScaleFix,h.minScale),o.uniform4fv(n.uFaceA,h.faceA),o.uniform4fv(n.uFaceB,h.faceB),o.uniform4fv(n.uFaceC,h.faceC),o.uniform4fv(n.uFaceD,h.faceD),o.uniform3fv(n.uGlow,h.glow),o.uniform3fv(n.uShadow,e.shadow),o.uniform1f(n.uFloor,e.floor),o.uniform1f(n.uLift,f),o.uniform1f(n.uExposure,e.exposure*h.exposure),o.uniform3fv(n.uAlbedo,e.albedo),o.uniform1f(n.uGlowPool,l.glowPool??0),o.uniform4fv(n.uFxA,e.fx.a),o.uniform4fv(n.uFxB,e.fx.b),o.uniform4fv(n.uFxC,e.fx.c),o.uniform1i(n.uFxCount,e.fx.count),a.character.reveal&&o.uniform3fv(n.uReveal,e.reveal??It),o.drawArrays(o.TRIANGLES,0,3),this.target.globalCompositeOperation="copy",this.target.drawImage(r.canvas,0,r.canvas.height-i,s,i,0,0,s,i),!0}dispose(){this.character=null}};var Pt=/^#[0-9a-f]{6}$/i;function Bt(t,e,a,r){if(!e.includes(a))throw new Error(`${t}: palette names material "${a}". Materials are: ${e.join(", ")}.`);if(!Pt.test(r))throw new Error(`${t}: palette colour for "${a}" must look like #rrggbb, got "${r}".`)}function Tt(t,e){let a=Object.keys(t.materials),r=new Map;for(let[o,s]of Object.entries(e))Bt(t.id,a,o,s),r.set(o,O(s));for(let[o,s]of Object.entries(t.materials)){let i=s.shadeOf;if(!i||r.has(o)||!(i in e))continue;let n=O(t.materials[i].color),l=O(s.color),h=r.get(i);r.set(o,[0,1,2].map(f=>Math.min(1,n[f]>.001?h[f]*l[f]/n[f]:l[f])))}return r}function ze(t,e){let a=t.albedo.slice();if(!e)return a;for(let[r,o]of Tt(t.spec,e))a.set(o,t.materials.indexOf(r)*3);return a}var Ee=class{members=new Set;frame=0;last=0;time=0;quality=1;slow=0;fast=0;add(e){this.members.add(e),this.start()}delete(e){this.members.delete(e),this.members.size||this.stop()}start(){this.frame||typeof requestAnimationFrame>"u"||(this.last=performance.now(),this.frame=requestAnimationFrame(this.loop))}stop(){cancelAnimationFrame(this.frame),this.frame=0}loop=e=>{this.frame=requestAnimationFrame(this.loop);let a=Math.max(0,e-this.last),r=Math.min(a/1e3,1/20);this.adapt(a),this.last=e,this.time+=r;for(let o of this.members)o.active&&o.tick(r,this.time,this.quality)};adapt(e){e>22&&e<200?this.slow++:this.slow=Math.max(0,this.slow-1),e<17.5?this.fast++:this.fast=0,this.slow>20?(this.quality=Math.max(.55,this.quality*.85),this.slow=0):this.fast>120&&this.quality<1&&(this.quality=Math.min(1,this.quality*1.08),this.fast=0)}},$e=new Ee;var Re=[1e6,1,1],Ot=new WeakMap,Vt=new WeakMap;function pt(t,e={}){let a=e.reveal?Vt:Ot,r=a.get(t);return r||a.set(t,r=st(t,e)),r}function Ce(){try{return W.shared(),!0}catch{return!1}}var me=class{constructor(e,a,r={}){this.canvas=e;if(this.seed=r.seed??Math.random(),this.palette=r.palette,this.options={interactive:r.interactive??!0,effects:r.effects??!0,speed:r.speed??1,maxPixelRatio:r.maxPixelRatio??2,shadow:r.shadow??[.05,.06,.12],floor:r.floor??1,exposure:r.exposure??1,framing:r.framing??1,respectReducedMotion:r.respectReducedMotion??!0,revealable:r.revealable??!1},this.renderer=new fe(e),this.load(a,r.state??"idle"),e.setAttribute("role","img"),this.reducedMotion=typeof matchMedia=="function"?matchMedia("(prefers-reduced-motion: reduce)"):null,typeof IntersectionObserver<"u"){let o=new IntersectionObserver(([s])=>this.visible=s.isIntersecting);o.observe(e),this.cleanup.push(()=>o.disconnect())}this.options.interactive&&this.listen(),$e.add(this)}character;brain;rig;fx;renderer;options;shown=Re;seed;palette;albedo;visible=!0;paused=!1;time=0;reducedMotion;stillFrames=0;drawn=!1;listeners={poke:new Set,state:new Set,ready:new Set};cleanup=[];source;get state(){return this.brain.state}get spec(){return this.source}get stats(){return this.character.stats}setState(e){if(!oe.includes(e))throw new Error(`Unknown state "${e}". Expected one of ${oe.join(", ")}.`);e!==this.brain.state&&(this.brain.setState(e),this.stillFrames=0,this.label(),this.emit("state",e))}setSpec(e,a){this.palette=a,this.load(e,this.brain.state)}setPalette(e){this.albedo=ze(this.character,e),this.palette=e,this.stillFrames=0}setSpeed(e){this.options.speed=Math.max(0,e)}setEffects(e){this.options.effects=e}reveal(e){if(!this.options.revealable)throw new Error("reveal() needs a mascot created with { revealable: true }");this.shown=e?[e.parts??Re[0],e.face===!1?0:1,e.paints===!1?0:1]:Re,this.stillFrames=0}poke(){this.brain.poke(),this.stillFrames=0,this.emit("poke",void 0)}pause(){this.paused=!0}play(){this.paused=!1}on(e,a){return this.listeners[e].add(a),()=>this.listeners[e].delete(a)}get active(){return!this.visible||this.paused?!1:!this.still||this.stillFrames<2}tick(e,a,r){let o=this.still,s=e*this.options.speed;if(o)for(let f=0;f<90;f++)this.brain.update(1/60);else this.brain.update(s),this.time+=s;let i=o?0:this.time,n=this.brain.pose;this.rig.update(n.root,n.channels,n.weights,i,o?0:s),!o&&this.options.effects?this.fx.update(s,n,this.rig):this.fx.count=0,n.events.length=0;let l=Math.min(devicePixelRatio||1,this.options.maxPixelRatio)*r,h=this.renderer.render({pose:n,bones:this.rig.inverse,fx:this.fx,albedo:this.albedo,time:i,width:Math.max(1,Math.round(this.canvas.clientWidth*l)),height:Math.max(1,Math.round(this.canvas.clientHeight*l)),shadow:this.options.shadow,floor:this.options.floor,exposure:this.options.exposure,framing:this.options.framing,reveal:this.shown});h&&o&&this.stillFrames++,h&&!this.drawn&&(this.drawn=!0,this.emit("ready",void 0))}get ready(){return this.drawn}dispose(){$e.delete(this),this.cleanup.forEach(e=>e()),this.listeners.poke.clear(),this.listeners.state.clear(),this.listeners.ready.clear(),this.renderer.dispose()}load(e,a){this.source=e,this.character=pt(e,{reveal:this.options.revealable}),this.albedo=ze(this.character,this.palette),this.renderer.load(this.character),this.brain=new ie(e.motion,this.seed),this.brain.setState(a),this.rig=new he(this.character.bones,this.character.acting),this.fx=new ne(this.character,ae(this.seed+.37)),this.stillFrames=0,this.label()}get still(){return this.options.respectReducedMotion&&(this.reducedMotion?.matches??!1)}emit(e,a){for(let r of this.listeners[e])r(a)}label(){this.canvas.hasAttribute("data-own-label")||this.canvas.setAttribute("aria-label",`${this.source.name}, ${this.brain.state}`)}listen(){let e=o=>{let s=this.canvas.getBoundingClientRect(),i=Math.max(s.width,1),n=(o.clientX-(s.left+s.width/2))/(i*1.1),l=(o.clientY-(s.top+s.height*.45))/(i*1.1);this.brain.pointer=Math.hypot(n,l)<3?{x:n,y:l}:null},a=()=>this.brain.pointer=null,r=()=>this.poke();window.addEventListener("pointermove",e,{passive:!0}),document.addEventListener("pointerleave",a),this.canvas.addEventListener("click",r),this.cleanup.push(()=>{window.removeEventListener("pointermove",e),document.removeEventListener("pointerleave",a),this.canvas.removeEventListener("click",r)})}};function Ae(t,e,a={}){let r=document.createElement("canvas");r.style.cssText="display:block;width:100%;height:100%;touch-action:manipulation",t.append(r);let o=new me(r,e,a),s=o.dispose.bind(o);return o.dispose=()=>{s(),r.remove()},o}var ht={id:"boo",name:"Boo",tagline:"Floats, glows from inside, trails motes, a hem that ripples",accent:"#8a6cf0",frame:{target:.78,radius:.92},bound:{y:.72,radius:.72},motion:{float:.22,hop:.12,squash:.8,snap:.8,talkSquash:.6},glowPool:.55,materials:{ghost:{color:"#eceaff",f0:.04,spec:.5,shininess:30,rim:1.4,sss:.4,sssColor:"#b9a4ff",emit:"#6f52d9",emitStrength:.06},bead:{color:"#1b1430",f0:.06,spec:2.2,shininess:400,rim:.2,gloss:1}},bones:[{name:"body",pivot:[0,0,0],drive:{rx:[["pitch",-.5]],ry:[["yaw",.7]],rz:[["roll",.6]]},wave:{rz:[.03,.45,0]}},{name:"armL",parent:"body",pivot:[-.36,.74,.04],drive:{rz:[["flap",-1.2]]},wave:{rz:[.08,.7,0]},jiggle:{axis:[-.8,-.6,0],length:.15,freq:2,damping:.2,maxAngle:.7}},{name:"armR",parent:"body",pivot:[.36,.74,.04],drive:{rz:[["flap",1.2]]},wave:{rz:[-.08,.7,1.6]},jiggle:{axis:[.8,-.6,0],length:.15,freq:2,damping:.2,maxAngle:.7}}],parts:[{bone:"body",shape:"sphere",at:[0,.88,0],radius:.4,material:"ghost"},{bone:"body",shape:"roundCone",from:[0,.88,0],to:[0,.4,0],r1:.4,r2:.47,material:"ghost"},{bone:"body",shape:"hem",y:.34,amplitude:.045,waves:6,speed:2.4,blend:.05,material:"ghost"},{bone:"armL",shape:"capsule",from:[0,0,0],to:[-.12,-.09,.02],radius:.07,blend:.08,material:"ghost"},{bone:"armR",shape:"capsule",from:[0,0,0],to:[.12,-.09,.02],radius:.07,blend:.08,material:"ghost"}],paints:[{bone:"body",on:["ghost"],kind:"sphere",at:[-.24,.78,.31],radius:.07,color:"#ffa3c4",soft:.6,opacity:.7},{bone:"body",on:["ghost"],kind:"sphere",at:[.24,.78,.31],radius:.07,color:"#ffa3c4",soft:.6,opacity:.7}],eyes:{kind:"bead",bone:"body",at:[[-.135,.9,.375],[.135,.9,.375]],radii:[.048,.072,.03],material:"bead"},face:{kind:"mouth",bone:"body",on:["ghost"],at:[0,.77,.38],width:.075,color:"#2a1a4a",tongue:"#ff7fa6"},anchors:{top:{bone:"body",at:[.16,1.2,.1]},mouth:{bone:"body",at:[0,.77,.4]},ear:{bone:"body",at:[-.42,.92,0]},center:{bone:"body",at:[0,.8,0]}},acting:{idle:{armL:{rz:[0,.1,.7,0]},armR:{rz:[0,.1,.7,1.3]}},thinking:{armR:{ry:-1.1,rz:.9},armL:{rz:.25}},listening:{armL:{rz:-1,rx:-.35}},speaking:{armL:{rz:[-.3,.3,1.2,0],rx:[-.3,.2,.9,0]},armR:{rz:[.3,.3,1.2,1.7],rx:[-.3,.2,.9,2.2]}},sleeping:{armL:{rz:.4},armR:{rz:-.4},body:{rz:.08}},working:{armL:{rx:[-.6,.15,6,0],rz:-.3},armR:{rx:[-.6,.15,6,Math.PI],rz:.3}},error:{armL:{rz:[-1,.25,10,0]},armR:{rz:[1,.25,10,1]}},surprised:{armL:{rz:-1.4,rx:-.4},armR:{rz:1.4,rx:-.4}},celebrating:{armL:{rz:[-1.6,.3,4,0]},armR:{rz:[1.6,.3,4,Math.PI]}},sad:{armL:{rz:.5},armR:{rz:-.5},body:{rz:.05}},happy:{armL:{rz:[-1.3,.35,3,0]},armR:{rz:[1.3,.35,3,1.2]}}},fx:{ambient:[{glyph:"mote",anchor:"center",rate:1.3,spread:.5,velocity:[0,.07,0],jitter:.06,wobble:.09,life:[2.2,3.2],size:[.04,.02],color:"#b49cff",glow:!0}],happy:[{glyph:"heart",anchor:"top",rate:1.2,spread:.2,velocity:[0,.22,.05],jitter:.12,wobble:.06,life:[1,1.3],size:[.04,.07],color:"#ff86b0"}]}};var ft={id:"bao",name:"Bao",tagline:"A chubby panda cub: round ears, eye patches, and a belly made for sitting",accent:"#2f3b4c",frame:{target:.46,radius:.62},bound:{y:.45,radius:.57},motion:{hop:.1,squash:1.2,snap:.9,talkSquash:.4},materials:{white:{color:"#f6f3ec",f0:.03,spec:.4,shininess:20,rim:1,sheen:.6,surface:{kind:"fur",scale:100,strength:.3,bone:"head"}},whiteBody:{color:"#f6f3ec",shadeOf:"white",f0:.03,spec:.4,shininess:20,rim:1,sheen:.6,surface:{kind:"fur",scale:100,strength:.3}},black:{color:"#26252b",f0:.03,spec:.4,shininess:20,rim:.9,sheen:.6,surface:{kind:"fur",scale:100,strength:.3}},nose:{color:"#1b1a1f",f0:.06,spec:1.8,shininess:200,rim:.3,gloss:.9}},bones:[{name:"body",pivot:[0,0,0],drive:{ry:[["yaw",.2]],rz:[["roll",.35]]},wave:{rz:[.02,.5,0]}},{name:"head",parent:"body",pivot:[0,.48,.02],drive:{rx:[["pitch",-1]],ry:[["yaw",.8]],rz:[["roll",.7]]}},{name:"armL",parent:"body",pivot:[-.22,.38,.06],rest:{rz:-.4},drive:{rz:[["flap",-1]]}},{name:"armR",parent:"body",pivot:[.22,.38,.06],rest:{rz:.4},drive:{rz:[["flap",1]]}}],parts:[{bone:"body",shape:"ellipsoid",at:[0,.26,0],radii:[.29,.27,.26],material:"whiteBody"},{bone:"body",shape:"ellipsoid",at:[-.15,.08,.14],radii:[.1,.08,.12],blend:.05,material:"black"},{bone:"body",shape:"ellipsoid",at:[.15,.08,.14],radii:[.1,.08,.12],blend:.05,material:"black"},{bone:"body",shape:"ellipsoid",at:[0,.42,-.01],radii:[.27,.07,.24],blend:.05,material:"black"},{bone:"armL",shape:"capsule",from:[0,0,0],to:[-.04,-.16,.06],radius:.07,blend:.04,material:"black"},{bone:"armR",shape:"capsule",from:[0,0,0],to:[.04,-.16,.06],radius:.07,blend:.04,material:"black"},{bone:"head",shape:"ellipsoid",at:[0,.14,0],radii:[.28,.24,.24],blend:.1,material:"white"},{bone:"head",shape:"ellipsoid",at:[0,.06,.18],radii:[.1,.07,.08],blend:.06,material:"white"},{bone:"head",shape:"ellipsoid",at:[0,.09,.26],radii:[.035,.022,.02],material:"nose"},{bone:"head",shape:"sphere",at:[-.2,.33,-.02],radius:.075,blend:.03,material:"black"},{bone:"head",shape:"sphere",at:[.2,.33,-.02],radius:.075,blend:.03,material:"black"}],paints:[{bone:"head",on:["white"],kind:"ellipse",at:[-.1,.15,.2],radii:[.06,.08],color:"#26252b",soft:.2},{bone:"head",on:["white"],kind:"ellipse",at:[.1,.15,.2],radii:[.06,.08],color:"#26252b",soft:.2},{bone:"head",on:["white"],kind:"sphere",at:[-.17,.05,.18],radius:.04,color:"#ffb3c1",soft:.6,opacity:.7},{bone:"head",on:["white"],kind:"sphere",at:[.17,.05,.18],radius:.04,color:"#ffb3c1",soft:.6,opacity:.7}],eyes:{kind:"ball",bone:"head",at:[[-.095,.16,.21],[.095,.16,.21]],radius:.04,iris:"#3a2a20",irisSize:.7,pupilSize:.5,lid:"black"},face:{kind:"mouth",bone:"head",on:["white"],at:[0,.035,.25],width:.04,color:"#26252b",tongue:"#ff8fa3"},anchors:{top:{bone:"head",at:[.15,.45,.05]},mouth:{bone:"head",at:[0,.035,.27]},ear:{bone:"head",at:[-.22,.33,0]},feet:{bone:"root",at:[0,.02,.18]}},acting:{idle:{armL:{rz:[0,.05,.5,0]}},thinking:{armR:{rz:1.5,rx:-1.2,ry:-.4},head:{rz:.1}},listening:{armL:{rz:-.6,rx:-.4}},speaking:{armL:{rz:[-.2,.2,1.2,0]},armR:{rz:[.2,.2,1.2,1.4]}},sleeping:{head:{rx:.25,rz:.15}},working:{armL:{rx:[-.8,.2,5,0]},armR:{rx:[-.8,.2,5,Math.PI]}},error:{armL:{rz:-1.6,rx:-.6},armR:{rz:1.6,rx:-.6}},surprised:{armL:{rz:-1.1},armR:{rz:1.1}},celebrating:{armL:{rz:[-2.2,.3,4,0]},armR:{rz:[2.2,.3,4,Math.PI]}},sad:{head:{rx:.3},armL:{rz:.1},armR:{rz:-.1}},happy:{armL:{rz:[-1.5,.3,3,0]},armR:{rz:[1.5,.3,3,1]}}},fx:{happy:[{glyph:"heart",anchor:"top",rate:1.2,velocity:[0,.22,.04],jitter:.1,life:[1,1.3],size:[.04,.06],color:"#ff86b0"}]}};var Fe={id:"zuffi",name:"Zuffi",tagline:"A soft blush-pink bunny with tall ears, little paws and sparkly eyes",accent:"#ff8fb1",frame:{target:.6,radius:.8},bound:{y:.6,radius:.7},motion:{hop:.2,squash:1.25,snap:1.1,talkSquash:.45},glowPool:.25,materials:{fur:{color:"#fff4f6",f0:.03,spec:.45,shininess:22,rim:1.1,sheen:.85,sss:.25,sssColor:"#ffc9d6",surface:{kind:"fur",scale:120,strength:.32,bone:"head"}},bodyFur:{color:"#fff4f6",shadeOf:"fur",f0:.03,spec:.45,shininess:22,rim:1.1,sheen:.85,sss:.25,sssColor:"#ffc9d6",surface:{kind:"fur",scale:120,strength:.32}},belly:{color:"#ffffff",shadeOf:"fur",f0:.03,spec:.35,shininess:18,rim:.9,sheen:.9,surface:{kind:"fur",scale:140,strength:.25}},earFur:{color:"#fff1f4",shadeOf:"fur",f0:.03,spec:.4,shininess:20,rim:1.3,sheen:.7,sss:.55,sssColor:"#ffb3c6"},nose:{color:"#ff7fa5",f0:.06,spec:1.8,shininess:180,rim:.3,gloss:.9}},bones:[{name:"body",pivot:[0,0,0],drive:{ry:[["yaw",.2]],rz:[["roll",.35]]}},{name:"head",parent:"body",pivot:[0,.44,.02],drive:{rx:[["pitch",-1]],ry:[["yaw",.8]],rz:[["roll",.7]]}},{name:"earL",parent:"head",pivot:[-.09,.32,-.02],rest:{rz:.16,rx:-.05},jiggle:{axis:[0,1,0],length:.34,freq:2.2,damping:.15,maxAngle:.7}},{name:"earR",parent:"head",pivot:[.09,.32,-.02],rest:{rz:-.22,rx:-.05},jiggle:{axis:[0,1,0],length:.34,freq:2.2,damping:.15,maxAngle:.7}},{name:"armL",parent:"body",pivot:[-.15,.32,.12],drive:{rz:[["flap",-.9]]},jiggle:{axis:[-.3,-1,.2],length:.1,freq:2.4,damping:.25,maxAngle:.5}},{name:"armR",parent:"body",pivot:[.15,.32,.12],drive:{rz:[["flap",.9]]},jiggle:{axis:[.3,-1,.2],length:.1,freq:2.4,damping:.25,maxAngle:.5}},{name:"tail",parent:"body",pivot:[0,.14,-.2],jiggle:{axis:[0,0,-1],length:.06,freq:4,damping:.2}}],parts:[{bone:"body",shape:"ellipsoid",at:[0,.22,0],radii:[.21,.23,.2],material:"bodyFur"},{bone:"body",shape:"ellipsoid",at:[0,.2,.09],radii:[.14,.15,.11],blend:.05,material:"belly"},{bone:"body",shape:"ellipsoid",at:[-.11,.04,.1],radii:[.075,.045,.12],blend:.04,material:"bodyFur"},{bone:"body",shape:"ellipsoid",at:[.11,.04,.1],radii:[.075,.045,.12],blend:.04,material:"bodyFur"},{bone:"armL",shape:"capsule",from:[0,0,0],to:[-.02,-.11,.05],radius:.045,blend:.05,material:"bodyFur"},{bone:"armR",shape:"capsule",from:[0,0,0],to:[.02,-.11,.05],radius:.045,blend:.05,material:"bodyFur"},{bone:"tail",shape:"sphere",at:[0,0,-.03],radius:.07,blend:.03,material:"bodyFur"},{bone:"head",shape:"ellipsoid",at:[0,.14,0],radii:[.26,.225,.22],blend:.1,material:"fur"},{bone:"head",shape:"ellipsoid",at:[-.06,.055,.17],radii:[.07,.055,.06],blend:.04,material:"fur"},{bone:"head",shape:"ellipsoid",at:[.06,.055,.17],radii:[.07,.055,.06],blend:.04,material:"fur"},{bone:"head",shape:"ellipsoid",at:[0,.095,.222],radii:[.03,.021,.018],material:"nose"},{bone:"earL",shape:"ellipsoid",at:[0,.21,0],radii:[.068,.23,.032],material:"earFur"},{bone:"earR",shape:"ellipsoid",at:[0,.21,0],radii:[.068,.23,.032],material:"earFur"}],paints:[{bone:"earL",on:["earFur"],kind:"ellipse",at:[0,.21,.032],radii:[.038,.17],color:"#ffb6ca",soft:.45},{bone:"earR",on:["earFur"],kind:"ellipse",at:[0,.21,.032],radii:[.038,.17],color:"#ffb6ca",soft:.45},{bone:"head",on:["fur"],kind:"sphere",at:[-.165,.07,.16],radius:.05,color:"#ff9fbc",soft:.6,opacity:.85},{bone:"head",on:["fur"],kind:"sphere",at:[.165,.07,.16],radius:.05,color:"#ff9fbc",soft:.6,opacity:.85}],eyes:{kind:"ball",bone:"head",at:[[-.1,.175,.17],[.1,.175,.17]],radius:.054,iris:"#3a1d2c",irisSize:.88,pupilSize:.55,lid:"fur"},face:{kind:"mouth",bone:"head",on:["fur"],at:[0,.03,.212],width:.038,color:"#5a2a3a",tongue:"#ff8fa3"},anchors:{top:{bone:"head",at:[.15,.52,.05]},mouth:{bone:"head",at:[0,.03,.24]},ear:{bone:"earL",at:[0,.21,0]},center:{bone:"body",at:[0,.35,0]},feet:{bone:"root",at:[0,.02,.15]}},acting:{idle:{armL:{rz:[0,.06,.8,0]},armR:{rz:[0,.06,.8,1.4]}},thinking:{earR:{rz:-.5},head:{rz:.1},armR:{rx:-1.5,rz:.4}},listening:{earL:{rz:.05,rx:-.25},earR:{rz:-.05,rx:-.25},armR:{rx:-2.2,rz:.9}},speaking:{armL:{rx:[-.4,.25,1.3,0]},armR:{rx:[-.4,.25,1.3,1.9]}},sleeping:{earL:{rz:1.2,rx:.5},earR:{rz:-1.4,rx:.5}},working:{armL:{rx:[-.7,.15,6,0]},armR:{rx:[-.7,.15,6,Math.PI]}},error:{earL:{rz:[.6,.2,9,0]},earR:{rz:[-.6,.2,9,1]},armL:{rx:-.9,rz:.6},armR:{rx:-.9,rz:-.6}},surprised:{earL:{rz:.02,rx:-.15},earR:{rz:-.02,rx:-.15},armL:{rx:-1.4},armR:{rx:-1.4}},celebrating:{earL:{rz:[.2,.3,4,0]},earR:{rz:[-.2,.3,4,Math.PI]},armL:{rz:[-1.8,.3,4,0]},armR:{rz:[1.8,.3,4,Math.PI]}},sad:{earL:{rz:1.4,rx:.6},earR:{rz:-1.4,rx:.6},armL:{rz:.2},armR:{rz:-.2}}},fx:{happy:[{glyph:"heart",anchor:"top",rate:1.2,velocity:[0,.22,.04],jitter:.1,life:[1,1.3],size:[.04,.06],color:"#ff8fb1"}]}};var jt={zuffi:Fe,boo:ht,bao:ft},q=null,mt="";function dt(t){let e=jt[t]||Fe;if(mt===e.id&&q)return;mt=e.id;let a=document.getElementById("stage");if(q){q.setSpec(e);return}q=Ae(a,e,{})}window.ZuffiMascot={supported:()=>Ce(),show:dt,state:t=>{q?.setState(t)},poke:()=>{q?.poke()},pause:()=>q?.pause(),play:()=>q?.play()};var qe=new URLSearchParams(location.search);dt(qe.get("c")||"zuffi");qe.get("s")&&q?.setState(qe.get("s"));})();
