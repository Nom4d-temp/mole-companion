-- Offline tests: Lua 5.4. Run from repository root or its parent.
local path=io.open('companion.lua') and 'companion.lua' or 'mole-companion/companion.lua'
local h=assert(io.open(path));local source=h:read('*a');h:close()
local M=assert(load(source,'companion'))('--test')
local tests=0
local function check(name,fn) local ok,err=pcall(fn);assert(ok,name..': '..tostring(err));tests=tests+1 end
local function state() return M.new({{id=4,name='North',token='secret-token'}}) end
local function packet(kind,seq)
  return {v=1,kind=kind or 'status',seq=seq or 1,session='boot-a',job='job-a',token='secret-token',phase='Mining',y=12,depth=52,right=3,forward=5,fuel=900}
end
check('unknown sender ignored',function() assert(not M.receive(state(),5,packet(),1)) end)
check('wrong token ignored',function() local m=packet();m.token='wrong';assert(not M.receive(state(),4,m,1)) end)
check('protocol version rejected',function() local m=packet();m.v=9;assert(not M.receive(state(),4,m,1)) end)
check('status and stale contact',function() local s=state();assert(M.receive(s,4,packet(),10));assert(M.online(s.turtles[4],25));assert(not M.online(s.turtles[4],26));assert(s.turtles[4].status.y==12) end)
check('duplicate and reordered status',function() local s=state();assert(M.receive(s,4,packet(nil,3),1));assert(not M.receive(s,4,packet(nil,2),2));assert(not M.receive(s,4,packet(nil,3),2)) end)
check('restart accepts sequence reset',function() local s=state();M.receive(s,4,packet(nil,8),1);local m=packet();m.session='boot-b';assert(M.receive(s,4,m,2));assert(not M.receive(s,4,packet(nil,9),3)) end)
check('non-status cannot change session',function() local s=state();M.receive(s,4,packet(),1);local m=packet('log');m.text='test';m.session='new';assert(not M.receive(s,4,m,2)) end)
check('invalid coordinates rejected',function() for _,v in ipairs({'12',math.huge}) do local m=packet();m.y=v;assert(not M.receive(state(),4,m,1)) end end)
check('unlimited fuel and uncertain position',function() local s=state();local m=packet();m.fuel='unlimited';m.uncertain=true;assert(M.receive(s,4,m,1));assert(s.turtles[4].status.uncertain) end)
check('bounded log with independent sequences',function() local s=state();M.receive(s,4,packet(nil,100),1);for i=1,120 do local m=packet('log',i);m.text='Line '..i;assert(M.receive(s,4,m,i)) end;assert(#s.turtles[4].logs==80 and s.turtles[4].logs[1]=='Line 41') end)
check('discovery count snapshots and deduplication',function() local s=state();M.receive(s,4,packet(),1);local m=packet('discovery');m.block='mod:ore';m.count=3;assert(M.receive(s,4,m,2));assert(not M.receive(s,4,m,2));m.seq=2;m.count=8;assert(M.receive(s,4,m,3));assert(s.turtles[4].blocks['mod:ore'].count==8 and #s.turtles[4].logs==0) end)
check('discovery limits',function() local s=state();M.receive(s,4,packet(),1);for i=1,128 do local m=packet('discovery',i);m.block='mod:ore'..i;m.count=1;assert(M.receive(s,4,m,2)) end;local m=packet('discovery',129);m.block='mod:extra';m.count=1;assert(not M.receive(s,4,m,2)) end)
check('offline return refused',function() assert(not M.command(state(),4,10)) end)
check('return retries preserve request id',function() local s=state();M.receive(s,4,packet(),1);local p=M.command(s,4,1);local sent={};for n=4,13,3 do M.tick(s,n,function(_,m) sent[#sent+1]=m.request end) end;assert(#sent==3);for _,id in ipairs(sent) do assert(id==p.request) end;assert(s.turtles[4].command.result=='unconfirmed') end)
check('ack stops retries and completion cannot regress',function() local s=state();M.receive(s,4,packet(),1);local p=M.command(s,4,2);local m=packet('ack');m.request=p.request;m.result='accepted';assert(M.receive(s,4,m,3));M.tick(s,7,function() error('Retried accepted request') end);m.seq=2;m.result='completed';assert(M.receive(s,4,m,8));m.seq=3;m.result='accepted';assert(not M.receive(s,4,m,9)) end)
check('wrong acknowledgement ignored',function() local s=state();M.receive(s,4,packet(),1);M.command(s,4,2);local m=packet('ack');m.request='wrong';m.result='accepted';assert(not M.receive(s,4,m,3)) end)
check('duplicate return refused',function() local s=state();M.receive(s,4,packet(),1);assert(M.command(s,4,2));assert(not M.command(s,4,3)) end)
check('pairing persistence excludes live data',function() local s=state();M.receive(s,4,packet(),1);local p=M.pairs(s);assert(p[1].id==4 and p[1].token=='secret-token' and not p[1].status);assert(not M.new(p).turtles[4].lastSeen) end)
check('fleet cap and duplicate ids',function() local s=M.new();for i=1,32 do assert(M.add(s,i,'Turtle '..i,'secret-token')) end;assert(not M.add(s,33,'extra','secret-token'));assert(not M.add(s,1,'duplicate','secret-token')) end)
check('explicit re-pair resets session and token',function() local s=state();M.receive(s,4,packet(),1);assert(M.repair(s,4,'Renamed','new-secret'));assert(not s.turtles[4].lastSeen and #s.order==1);assert(not M.receive(s,4,packet(),2)) end)
check('pair welcome retries until first report',function() local s=state();s.turtles[4].welcome={packet={},sent=0,expires=30};local n=0;M.tick(s,3,function() n=n+1 end);assert(n==1);M.receive(s,4,packet(),4);M.tick(s,6,function() error('Continued welcome') end);assert(not s.turtles[4].welcome) end)
check('wrap preserves long ids on narrow monitors',function() local rows=M.wrap('examplemod:very_long_ore_identifier',18);assert(table.concat(rows)=='examplemod:very_long_ore_identifier');for _,line in ipairs(rows) do assert(#line<=18) end end)
check('control characters sanitized',function() assert(M.wrap('a\nb',39)[1]=='a b') end)
print('PASS: '..tests..' companion protocol/state tests')

-- Full application smoke tests: no Minecraft required. Render on 39x12 surfaces.
local function application(events,demo,hardwareNames,command,smallMonitor)
  local env=setmetatable({},{__index=_G});local files={};local saved={};local writes=0;local redraws=0;local timer=0;local packets={}
  local function surface(small)
    local w,h=small and 7 or 39,small and 5 or 12
    local rows={};local y=1
    return {getSize=function() return w,h end,setTextScale=function(n) assert(n==0.5);if small then w,h=15,10 end end,clear=function() redraws=redraws+1;rows={} end,
      setCursorPos=function(x,row) assert(x==1 and row>=1 and row<=h);y=row end,
      write=function(v) assert(#v<=w,'Screen overflow');rows[y]=v end},function() return rows end
  end
  local terminal=surface();local monitor,getRows=surface(smallMonitor);local present=true
  env.term=terminal
  env.fs={exists=function(p) return files[p]~=nil end,makeDir=function() end,delete=function(p) files[p]=nil end,
    move=function(a,b) assert(files[a] and not files[b]);files[b]=files[a];files[a]=nil end,
    open=function(p,mode) return {readAll=function() return files[p] end,write=function(v) writes=writes+1;files[p]=v end,close=function() end} end}
  env.textutils={serialize=function(v) saved[#saved+1]=v;return tostring(#saved) end,unserialize=function(v) return saved[tonumber(v)] end}
  local wireless={isWireless=function() return true end};local wired={isWireless=function() return false end}
  env.peripheral={getNames=function() return hardwareNames or {'monitor','wireless'} end,
    hasType=function(n,t) return n=='monitor' and t=='monitor' or (n=='wireless' or n=='wired') and t=='modem' end,
    wrap=function(n) return n=='monitor' and monitor or n=='wired' and wired or wireless end,
    isPresent=function(n) return n~='monitor' or present end}
  env.rednet={open=function() end,send=function(id,msg) if msg.kind=='paired' or msg.kind=='pair_verified' or msg.kind=='pong' or msg.kind=='command' and not demo then packets[#packets+1]=msg;return true end;error('Demo or unpaired station sent a turtle command') end}
  env.keys={left=1,right=2,tab=3,escape=4,up=5,down=6}
  env.os={epoch=function() return 10000 end,getComputerID=function() return 7 end,startTimer=function() timer=timer+1;return timer end,
    pullEvent=function() local e=table.remove(events,1);assert(e,'App did not close');if type(e)=='function' then e=e(getRows(),packets) end;if e[1]=='detach' then present=false;return 'peripheral_detach','monitor' end;return table.unpack(e) end}
  local output={};env.print=function(v) output[#output+1]=v end;env.write=function() end;env.read=function() return 'q' end
  local argument=command or (demo and 'demo' or 'start')
  if command=='overview' then argument=nil end
  assert(load(source,'companion','t',env))(argument)
  return {writes=writes,redraws=redraws,rows=getRows(),output=table.concat(output,'\n')}
end
check('station starts and quits without touching turtles',function() local r=application({{'char','q'}});assert(r.writes>0 and r.redraws>0) end)
check('demo writes no pairing configuration and sends no commands',function() local r=application({{'char','r'},{'char','d'},{'key',2},{'key',5},{'char','p'},{'char','q'}},true);assert(r.writes==0) end)
check('missing hardware gives retry instructions',function() local r=application({},false,{});assert(r.output:find('Place a monitor next to this computer.',1,true)) end)
check('wired modem refused',function() local r=application({},false,{'monitor','wired'});assert(r.output:find('wired modem cannot contact turtles',1,true)) end)
check('detached monitor does not crash station',function() application({{'detach'},{'timer',1},{'char','q'}}) end)
check('malformed new status cannot retire active session',function() local s=state();M.receive(s,4,packet(),1);local m=packet();m.session='bad';m.y='wrong';assert(not M.receive(s,4,m,2));assert(s.turtles[4].session=='boot-a');assert(M.receive(s,4,packet(nil,2),3)) end)
print('PASS: '..tests..' companion tests including full-app hardware/UI simulations')

check('new job clears old discoveries, old job packets ignored',function()
 local s=state();M.receive(s,4,packet(),1);local d=packet('discovery');d.block='mod:ore';d.count=1;assert(M.receive(s,4,d,2))
 local m=packet(nil,2);m.job='job-b';assert(M.receive(s,4,m,3));assert(not next(s.turtles[4].blocks))
 d.seq=2;assert(not M.receive(s,4,d,4))
end)
print('PASS: '..tests..' total companion checks')
local function maintenanceCase(command,reply,mode)
 local env=setmetatable({},{__index=_G});local files={companion='old program',['mole-companion-data/config']='old pairing',['mole-companion-data/config.backup']='old backup',startup='custom startup'}
 local closed=false;local output={}
 env.shell={getRunningProgram=function() return 'companion' end}
 env.print=function(v) output[#output+1]=v end;env.write=function() end;env.read=function() return reply or 'yes' end
 env.os={epoch=function() return 1234 end}
 env.fs={exists=function(p) return files[p]~=nil end,
  delete=function(p) for k in pairs(files) do if k==p or k:sub(1,#p+1)==p..'/' then files[k]=nil end end end,
  move=function(a,b) if mode=='movefail' then error('move failed') end;assert(files[a] and not files[b]);files[b]=files[a];files[a]=nil end,
  open=function(p,m) if m=='r' and not files[p] then return nil end;return {readAll=function() return files[p] end,write=function(v) files[p]=v end,close=function() end} end}
 env.http={get=function(url,headers)
  assert(url:find('?update=',1,true) and headers['Cache-Control']=='no-cache')
  if mode=='offline' then return nil,'offline' end
  return {readAll=function() return mode=='invalid' and 'not Lua' or source end,close=function() closed=true end}
 end}
 assert(load(source,'companion','t',env))(command)
 assert(files.startup=='custom startup','Modified unrelated startup')
 return files,closed,table.concat(output,'\n')
end
check('remove deletes program and settings without backup',function() local f=maintenanceCase('remove');assert(not f.companion and not f['mole-companion-data/config'] and not f['mole-companion-data/config.backup']) end)
check('remove cancellation preserves installation',function() local f=maintenanceCase('remove','no');assert(f.companion=='old program' and f['mole-companion-data/config']) end)
check('update clean installs even same version',function() local f,closed=maintenanceCase('update');assert(f.companion==source and not f['mole-companion-data/config'] and not f['companion.update-download'] and not f['companion.update-backup'] and closed) end)
check('failed download preserves settings',function() local f=maintenanceCase('update',nil,'offline');assert(f.companion=='old program' and f['mole-companion-data/config']) end)
check('invalid download preserves settings',function() local f,closed=maintenanceCase('update',nil,'invalid');assert(f.companion=='old program' and f['mole-companion-data/config'] and closed) end)
check('failed replacement restores program in memory without backup',function() local f=maintenanceCase('update',nil,'movefail');assert(f.companion=='old program' and f['mole-companion-data/config'] and not f['companion.update-download']) end)
print('PASS: '..tests..' total companion checks')

check('pairing acknowledgement distinguishes waiting for Mole',function()
 local s=state();s.turtles[4].welcome={packet={code='123456'}}
 local reply=M.control(s,4,{v=1,kind='pair_ready',token='secret-token',code='123456'},5)
 assert(reply.kind=='pair_verified' and s.turtles[4].awaitingMole and not s.turtles[4].welcome)
 assert(not M.control(s,9,{v=1,kind='pair_ready',token='secret-token',code='123456'},5))
end)
check('connection check validates token and echoes nonce',function()
 local s=state();local p={v=1,kind='ping',token='secret-token',nonce='abc'}
 assert(M.control(s,4,p,5).nonce=='abc');p.token='wrong';assert(not M.control(s,4,p,6))
end)
check('pair wizard shows separate ID/code and confirms connection',function()
 local pin
 local r=application({{'char','p'},function(rows)
   assert(rows[3]=='STATION COMPUTER ID: 7','Missing labelled station ID')
   pin=assert(rows[4]:match('^PAIRING CODE: (%d+)$'),'Missing labelled code')
   return {'rednet_message',21,{v=1,kind='pair_hello',code=pin,wireless=true,name='North'},M.protocol}
 end,{'char','y'},function(_,packets)
   local paired=packets[#packets];assert(paired.kind=='paired')
   return {'rednet_message',21,{v=1,kind='pair_ready',code=pin,token=paired.token},M.protocol}
 end,{'char','q'}},false,nil,'pair')
 assert(r.output:find('Pairing complete.',1,true),'Pair command did not finish')
 assert(table.concat(r.rows,'\n'):find('Paired - waiting for Mole to run',1,true),'Pairing looked disconnected before mining')
end)
print('PASS: '..tests..' total companion checks')

check('plain companion only shows guide, needs no hardware',function()
 local r=application({},false,{},'overview');assert(r.writes==0 and r.redraws==0 and r.output:find('companion start',1,true) and r.output:find('companion pair',1,true))
end)
check('pair command opens wizard immediately and escape exits',function()
 local r=application({function(rows)
   assert(rows[3]=='STATION COMPUTER ID: 7' and rows[4]:find('PAIRING CODE:',1,true),'Pair command did not open wizard')
   return {'key',4}
 end},false,nil,'pair')
 assert(r.output:find('Use companion start for the display.',1,true))
end)
check('start opens status without starting pairing',function()
 application({function(rows)
   assert(not table.concat(rows,'\n'):find('PAIRING CODE:',1,true),'Start automatically entered pairing')
   return {'char','q'}
 end})
end)
print('PASS: '..tests..' total companion checks')

check('single-block monitor scales down and shows turtle telemetry',function()
 local r=application({function(rows)
   assert(rows[3]=='Mining','Small monitor missing turtle state')
   assert(rows[4]:find('Y 18 D 46',1,true),'Small monitor missing Y/depth')
   assert(rows[5]=='Fuel 1450','Small monitor missing fuel')
   assert(rows[10]=='[<][>][R]','Compact buttons missing')
   return {'char','q'}
 end},true,nil,nil,true)
 assert(not table.concat(r.rows,'\n'):find('Monitor too small',1,true))
end)
check('compact pairing preserves full station ID and code',function()
 application({function(rows)
   assert(rows[2]=='Station ID:' and rows[3]=='7','Compact pairing lost ID')
   assert(rows[4]=='Pairing code:' and rows[5]:match('^%d%d%d%d%d%d$'),'Compact pairing lost code')
   return {'key',4}
 end},false,nil,'pair',true)
end)
print('PASS: '..tests..' total companion checks')

check('return notice follows acknowledged state',function()
 assert(M.returnNotice({result='sent'}):find('waiting',1,true))
 for _,result in ipairs({'accepted','completed','rejected','unconfirmed'}) do assert(not M.returnNotice({result=result}):find('waiting',1,true),'Stale waiting notice') end
end)
check('display clears waiting notice on acceptance and completion',function()
 local pin,token,request
 application({{'char','p'},function(rows)
   pin=assert(rows[4]:match('PAIRING CODE: (%d+)'))
   return {'rednet_message',21,{v=1,kind='pair_hello',code=pin,wireless=true,name='North'},M.protocol}
 end,{'char','y'},function(_,packets)
   token=packets[#packets].token
   return {'rednet_message',21,{v=1,kind='pair_ready',code=pin,token=token},M.protocol}
 end,function()
   return {'rednet_message',21,{v=1,kind='status',session='boot',seq=1,job='job',token=token,phase='Mining',y=20,depth=40,right=1,forward=2,fuel=1000},M.protocol}
 end,{'char','r'},{'char','y'},function(rows,packets)
   assert(rows[10]=='Return sent; waiting for reply.')
   request=packets[#packets].request
   return {'rednet_message',21,{v=1,kind='ack',session='boot',seq=1,token=token,request=request,result='accepted'},M.protocol}
 end,function(rows)
   assert(rows[10]=='Return accepted; heading home.','Waiting notice survived acceptance')
   return {'rednet_message',21,{v=1,kind='ack',session='boot',seq=2,token=token,request=request,result='completed'},M.protocol}
 end,function(rows)
   assert(rows[10]=='Home and paused.','Waiting notice survived completion')
   return {'char','q'}
 end})
end)
print('PASS: '..tests..' total companion checks')
check('resuming work clears completed return',function()
 for _,phase in ipairs({'Mining','Returning to work','At the chest','Returning home','Recovering position','Emergency escape'}) do
  local s=state();M.receive(s,4,packet(),1);s.turtles[4].command={id='old',result='completed'}
  local m=packet(nil,2);m.phase=phase;assert(M.receive(s,4,m,2));assert(not s.turtles[4].command)
 end
end)
check('new quarry clears return but active return stays visible',function()
 local s=state();M.receive(s,4,packet(),1);s.turtles[4].command={id='active',result='accepted'}
 assert(M.receive(s,4,packet(nil,2),2));assert(s.turtles[4].command)
 local m=packet(nil,3);m.job='new-job';assert(M.receive(s,4,m,3));assert(not s.turtles[4].command)
end)
print('PASS: '..tests..' total companion checks')

check('inventory occupancy is bounded and optional',function()
 local s=state();local m=packet();m.inventory=9;assert(M.receive(s,4,m,1));assert(s.turtles[4].status.inventory==9)
 m.seq=2;m.inventory=17;assert(M.receive(s,4,m,2));assert(s.turtles[4].status.inventory==nil)
end)
print('PASS: '..tests..' total companion checks')
