import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [out, ffmpeg, ffprobe, font] = process.argv.slice(2);
if(!font) throw Error('Usage: node render.mjs OUTPUT_DIR FFMPEG FFPROBE FONT_TTF');
const dir=path.resolve(out);fs.mkdirSync(path.join(dir,'edit'),{recursive:true});
fs.copyFileSync(font,path.join(dir,'edit','font.ttf'));
const edit=path.join(dir,'edit');
function run(args){const r=spawnSync(ffmpeg,['-hide_banner','-loglevel','error','-y',...args],{cwd:edit,encoding:'utf8'});if(r.status!==0)throw Error(r.stderr);}
const scene=(file,start,duration,chapter,title,sub,crop=400,note='')=>({file,start,duration,chapter,title,sub,crop,note});
const scenes=[
scene('home',1,6,'CAMPUS JOURNAL / INTRO','学习通课业手记','把课程、作业与截止时间，收进一本手记。',400,'基于公开版 1.6.71 的独立演示构建'),
scene('home',19,12,'01 / 作业时间轴','下一份作业，\n一眼就找到。','按日期整理作业，查看课程与截止时刻。',510,'日期待确认的作业单独保留，不猜测截止时间'),
scene('home',34,6,'01 / 作业详情','打开一项，\n看清截止。','作业详情保留具体时刻与状态。',360,'作答与提交仍需在学习通完成'),
scene('sync',44,9,'02 / 课程同步 · 演示数据源','轻点刷新，\n看见更新。','真实同步交互，由隔离合成响应驱动。',440,'本片不代表学习通真实联网同步验证'),
scene('sync',112,6,'02 / 课程管理 · 演示数据源','关注的课程，\n放在眼前。','四门虚拟课程，按需管理关注范围。',330,'虚拟账号：小禾 / demo-xiaohe'),
scene('calendar',34,10,'03 / 截止日历','把截止日期，\n放进日历。','点选日期，查看当天需要处理的作业。',420,'首页与日历使用同一组作业数据'),
scene('calendar',46.5,5,'03 / 当日作业','哪一天，\n要交哪一份。','同一天的课程作业，集中查看。',550,'截止时刻按应用显示的北京时间展示'),
scene('reminder',98,4,'04 / 本地提醒','提前准备，\n从容一点。','查看提醒设置和系统通知权限。',550,'提醒投递受权限、省电及系统调度影响'),
scene('notification',8,4,'04 / 提醒体检','发一条通知，\n实际确认。','通过应用内按钮发送原生测试通知。',1070,'真实 Android 通知投递，不使用合成通知画面'),
scene('notification-window',1,6,'04 / 系统通知实录','提醒，\n真实出现。','在 Android 通知栏确认测试通知。',470,'测试通知可见，不代表未来后台提醒必达'),
scene('personal',110,4,'05 / 个人记录','自己的进度，\n随手记下。','勾选清单步骤，保留自己的学习备注。',670,'个人清单完成不代表学习通已提交'),
scene('save',20,4,'05 / 保存记录','做过的事，\n留在手记里。','点击保存，让个人清单留在本机。',1050,'虚拟数据保存在独立演示包中'),
scene('statistics',40,7,'05 / 课业统计','完成了多少，\n心里有数。','查看完成比例与各课程待处理数量。',300,'合成样例：共 12 份作业，已完成 3 份'),
scene('home',2,7,'ANDROID / 下载体验','从下一份作业，\n开始记录。','首次安装下载 1.6.71 APK',400,'github.com/arrry-07/chaoxing-journal')
];
let elapsed=0;let srt=[];
const stamp=s=>new Date(s*1000).toISOString().slice(11,23).replace('.',',');
for(let i=0;i<scenes.length;i++){
 const s=scenes[i];
 const probe=spawnSync(ffprobe,['-v','error','-show_streams','-show_format','-of','json',path.join(dir,'raw',s.file+'.mp4')],{encoding:'utf8'});
 if(probe.status!==0)throw Error(probe.stderr);const metadata=JSON.parse(probe.stdout);if(+metadata.format.duration<s.start+s.duration)throw Error('Clip too short: '+s.file);
 fs.writeFileSync(path.join(edit,'probe-'+s.file+'.json'),probe.stdout);
 const texts={brand:'学习通课业手记  /  PROJECT DEMO',chapter:s.chapter,title:s.title,sub:s.sub,note:s.note,footer:'基于 1.6.71 · 虚拟账号与合成数据 · 真实 App 界面录制',counter:String(i+1).padStart(2,'0')+' / '+scenes.length,close:'界面特写 / DETAIL'};
 for(const [k,v]of Object.entries(texts))fs.writeFileSync(path.join(edit,k+'.txt'),v.replaceAll('\\n','\n'));
 const draw=(k,size,x,y,color='0x243e34')=>'drawtext=fontfile=font.ttf:textfile='+k+'.txt:fontsize='+size+':fontcolor='+color+':x='+x+':y='+y+':line_spacing=16';
 const bg=['drawbox=x=1160:y=90:w=2:h=880:color=0xd8d8ca:t=fill','drawbox=x=120:y=184:w=68:h=5:color=0xa36b42:t=fill',draw('brand',24,120,54),draw('chapter',25,120,131,'0x8c613f'),draw('title',72,114,226),draw('sub',29,120,418),draw('note',25,120,944,'0x58665a'),draw('footer',23,120,1025,'0x657062'),draw('counter',23,1684,1025,'0x657062'),draw('close',21,120,482,'0x657062')].join(',');
 const z='min(1.025,1+on*0.000035)';
 const graph='[0:v]fps=30,setpts=PTS-STARTPTS,split=2[full][detail];[full]scale=480:854,setsar=1[phone];[detail]crop=900:390:0:'+s.crop+',scale=900:390,zoompan=z='+"'"+z+"'"+':x=iw/2-iw/zoom/2:y=ih/2-ih/zoom/2:d=1:s=900x390:fps=30[close];[1:v]'+bg+'[base];[base][phone]overlay=1260:100[a];[a][close]overlay=120:528,drawbox=x=120:y=998:w='+Math.round(1680*(elapsed+s.duration)/90)+':h=3:color=0xa36b42:t=fill,fade=t=in:st=0:d=0.15,format=yuv420p[v]';
 run(['-ss',String(s.start),'-t',String(s.duration),'-i',path.join(dir,'raw',s.file+'.mp4'),'-f','lavfi','-i','color=c=0xf6f3e9:s=1920x1080:r=30','-filter_complex',graph,'-map','[v]','-an','-t',String(s.duration),'-c:v','libx264','-crf','19','-preset','fast','-threads','4','-movflags','+faststart','part-'+String(i).padStart(2,'0')+'.mp4']);
 srt.push(String(i+1)+'\n'+stamp(elapsed)+' --> '+stamp(elapsed+s.duration)+'\n'+s.sub+'\n'+s.note+'\n');elapsed+=s.duration;process.stdout.write('Rendered '+(i+1)+'/'+scenes.length+'\n');
}
fs.writeFileSync(path.join(edit,'concat.txt'),scenes.map((_,i)=>"file 'part-"+String(i).padStart(2,'0')+".mp4'").join('\n'));
run(['-f','concat','-safe','0','-i','concat.txt','-c','copy','-movflags','+faststart',path.join(dir,'学习通课业手记-项目演示-1080p.mp4')]);
fs.writeFileSync(path.join(dir,'字幕.srt'),srt.join('\n'));fs.writeFileSync(path.join(dir,'edit-decision-list.json'),JSON.stringify(scenes,null,2));

