-- Mole Companion v0.3.5 - optional CC:Tweaked monitoring station.
-- Optional station for Mole 1.6.0+. No turtle is modified here.
local argv={...}
local VERSION='0.3.5'
local PROTOCOL='mole-companion/1'
local M={protocol=PROTOCOL}
local function text(v,limit)
  if type(v)~='string' then return nil end
  return v:gsub('[%c]',' '):sub(1,limit or 160)
end
local function number(v) return type(v)=='number' and v==v and math.abs(v)~=math.huge end
local function integer(v) return number(v) and v%1==0 end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
function M.new(pairs)
  local state={turtles={},order={},selected=1,serial=0}
  for _,p in ipairs(pairs or {}) do
    if integer(p.id) and p.id>=0 and text(p.token,96) and #p.token>=8 and not state.turtles[p.id] and #state.order<32 then
      state.turtles[p.id]={id=p.id,name=text(p.name,32) or 'Turtle '..p.id,token=p.token,logs={},blocks={},lastSeen=nil,sequences={}}
      state.order[#state.order+1]=p.id
    end
  end
  return state
end
function M.pairs(state)
  local result={}
  for _,id in ipairs(state.order) do local t=state.turtles[id];result[#result+1]={id=id,name=t.name,token=t.token} end
  return result
end
function M.add(state,id,name,token)
  if not integer(id) or id<0 or state.turtles[id] or #state.order>=32 or not text(token,96) or #token<8 then return false end
  state.turtles[id]={id=id,name=text(name,32) or 'Turtle '..id,token=token,logs={},blocks={},sequences={}}
  state.order[#state.order+1]=id;state.selected=#state.order;return true
end
function M.repair(state,id,name,token)
  local t=state.turtles[id]
  if not t then return M.add(state,id,name,token) end
  if not text(token,96) or #token<8 then return false end
  t.token=token;t.name=text(name,32) or t.name;t.session=nil;t.retired={};t.sequences={};t.lastSeen=nil;t.command=nil;t.status=nil;t.statusAt=nil;t.pairReady=nil;t.awaitingMole=nil
  return true
end
local function addLog(t,line)
  t.logs[#t.logs+1]=line
  if #t.logs>80 then table.remove(t.logs,1) end
end
function M.receive(state,sender,msg,now)
  local t=state.turtles[sender]
  if not t or type(msg)~='table' or msg.v~=1 or msg.token~=t.token then return false end
  if not text(msg.session,48) or #msg.session==0 or #msg.session>48 or not integer(msg.seq) or msg.seq<1 then return false end
  if msg.kind~='status' and msg.kind~='log' and msg.kind~='discovery' and msg.kind~='ack' then return false end
  if msg.kind=='status' and (not text(msg.job,64) or #msg.job==0 or #msg.job>64 or not text(msg.phase,32) or not number(msg.y) or not number(msg.depth) or not number(msg.right) or not number(msg.forward)
    or not (number(msg.fuel) and msg.fuel>=0 or msg.fuel=='unlimited')) then return false end
  -- A new boot session begins with status. Old packets cannot switch it back.
  if t.session~=msg.session then
    if msg.kind~='status' then return false end
    t.retired=t.retired or {}
    if t.retired[msg.session] then return false end
    if t.session then
      if count(t.retired)>=32 then t.status.detail='Re-pair this turtle to refresh its connection.';return false end
      t.retired[t.session]=true
    end
    t.session=msg.session;t.sequences={}
  end
  if msg.seq<=(t.sequences[msg.kind] or 0) then return false end
  if msg.kind=='status' then
    if not text(msg.phase,32) or not number(msg.y) or not number(msg.depth) or not number(msg.right) or not number(msg.forward) then return false end
    if not (number(msg.fuel) and msg.fuel>=0 or msg.fuel=='unlimited') then return false end
    if t.job and t.job~=msg.job then t.blocks={};t.command=nil;addLog(t,'New quarry started.') end
    -- A finished return belongs to the previous pause, not resumed mining.
    if t.command and t.command.result=='completed' and (msg.phase=='Mining' or msg.phase=='Returning to work' or msg.phase=='At the chest' or msg.phase=='Returning home' or msg.phase=='Recovering position' or msg.phase=='Emergency escape') then t.command=nil end
    t.job=msg.job;t.statusAt=now;t.awaitingMole=false
    t.status={phase=text(msg.phase,32),y=msg.y,depth=msg.depth,right=msg.right,forward=msg.forward,
      fuel=msg.fuel,uncertain=msg.uncertain==true,detail=text(msg.detail,160),progress=text(msg.progress,64)}
  elseif msg.kind=='log' then
    local line=text(msg.text,256);if not line or #line==0 then return false end
    addLog(t,line)
  elseif msg.kind=='discovery' then
    if msg.job~=t.job then return false end
    local id=text(msg.block,120)
    if not id or not id:match('^[%w_.%-]+:[%w_./%-]+$') or not integer(msg.count) or msg.count<1 then return false end
    if not t.blocks[id] and count(t.blocks)>=128 then return false end
    local first=not t.blocks[id]
    t.blocks[id]={name=text(msg.name,64),count=msg.count}
    if first then addLog(t,'Unfamiliar block: '..id) end
  else
    local c=t.command
    if not c or msg.request~=c.id or (msg.result~='accepted' and msg.result~='completed' and msg.result~='rejected') then return false end
    if c.result=='completed' or c.result=='rejected' then return false end
    c.result=msg.result;c.detail=text(msg.detail,160);c.changed=now
    addLog(t,msg.result=='accepted' and 'Return accepted by turtle.' or msg.result=='completed' and 'Home and paused.' or 'Return rejected: '..(c.detail or 'See turtle status.'))
  end
  t.sequences[msg.kind]=msg.seq;t.lastSeen=now;return true
end
function M.control(state,sender,msg,now)
  local t=state.turtles[sender]
  if not t or type(msg)~='table' or msg.v~=1 or msg.token~=t.token then return nil end
  if msg.kind=='pair_ready' and type(msg.code)=='string' and msg.code:match('^%d%d%d%d%d%d$') then
    if t.welcome and msg.code~=t.welcome.packet.code then return nil end
    if not t.pairReady then addLog(t,'Connection checked. Waiting for Mole to run.') end
    t.pairReady=true;t.welcome=nil;t.lastSeen=now;t.awaitingMole=not t.status
    return {v=1,kind='pair_verified',token=t.token,code=msg.code}
  elseif msg.kind=='ping' and type(msg.nonce)=='string' and #msg.nonce<=96 then
    t.lastSeen=now;if not t.status then t.awaitingMole=true end
    return {v=1,kind='pong',token=t.token,nonce=msg.nonce}
  end
end
function M.online(t,now) return t.lastSeen~=nil and now-t.lastSeen<=15 end
function M.command(state,id,now)
  local t=state.turtles[id]
  if not t or not M.online(t,now) or not t.status then return nil,'No recent turtle report. Return was not sent.' end
  if t.command and (t.command.result=='sent' or t.command.result=='accepted') then return nil,'A return request is already pending.' end
  state.serial=state.serial+1
  local request=tostring(now)..'-'..state.serial
  t.command={id=request,result='sent',sent=now,attempts=0,changed=now}
  return {v=1,kind='command',action='return',token=t.token,request=request,session=t.session}
end
function M.returnNotice(command)
  local notices={sent='Return sent; waiting for reply.',accepted='Return accepted; heading home.',
    completed='Home and paused.',rejected='Return rejected. See turtle log.',unconfirmed='Return unconfirmed. Check connection.'}
  return command and notices[command.result] or ''
end
function M.tick(state,now,send)
  for _,id in ipairs(state.order) do
    local t=state.turtles[id];local c=t.command
    if t.welcome then
      if t.lastSeen or now>=t.welcome.expires then t.welcome=nil
      elseif now-t.welcome.sent>=3 then send(id,t.welcome.packet);t.welcome.sent=now end
    end
    if c and c.result=='sent' then
      if now-c.sent>=12 then c.result='unconfirmed';addLog(t,'Return not confirmed. Check connection before retrying.')
      elseif c.attempts<3 and now-c.changed>=3 then
        send(id,{v=1,kind='command',action='return',token=t.token,request=c.id,session=t.session})
        c.attempts=c.attempts+1;c.changed=now
      end
    end
  end
end
function M.wrap(line,width)
  local out={};line=text(line,256) or '';width=math.max(1,width)
  repeat
    if #line<=width then out[#out+1]=line;break end
    local cut=width
    for i=width,math.max(1,width-16),-1 do if line:sub(i,i)==' ' then cut=i;break end end
    out[#out+1]=line:sub(1,cut);line=line:sub(cut+1):gsub('^ +','')
  until false
  return out
end
if argv[1]=='--test' then return M end

local ROOT='mole-companion-data'
local function now() return os.epoch('utc')/1000 end
local function maintenance()
  local program=shell.getRunningProgram()
  if argv[1]=='remove' then
    print('Remove Companion and all pairings?')
    write('Are you sure? yes/no: ')
    if read():match('^%s*(.-)%s*$'):lower()~='yes' then print('Removal cancelled.');return end
    fs.delete(ROOT)
    for _,suffix in ipairs({'.update-download','.update-backup'}) do if fs.exists(program..suffix) then fs.delete(program..suffix) end end
    fs.delete(program)
    print('Companion successfully removed.')
    print('Remove any Companion startup line.')
    return
  end
  if not http or not http.get then print('Downloads disabled. Ask server owner.');return end
  print('Downloading a clean Companion install.')
  local response,why,failed=http.get('https://raw.githubusercontent.com/Nom4d-temp/mole-companion/main/companion.lua?update='..os.epoch('utc'),
    {['Cache-Control']='no-cache',['Pragma']='no-cache'})
  if not response then if failed then failed.close() end;print('Download failed. Current install kept.');return end
  local ok,source=pcall(response.readAll);response.close()
  if not ok or type(source)~='string' or not source:match('^%-%- Mole Companion v%d+%.%d+%.%d+') or not load(source,'@Companion update','t',_ENV) then
    print('Invalid download. Current install kept.');return
  end
  local temp=program..'.update-download'
  local old=fs.open(program,'r');local original=old and old.readAll();if old then old.close() end
  local installed=false
  local success,err=pcall(function()
    local h=assert(fs.open(temp,'w'));h.write(source);h.close()
    h=assert(fs.open(temp,'r'));local saved=h.readAll();h.close();assert(saved==source,'Saved download did not match')
    fs.delete(program);fs.move(temp,program);installed=true
    fs.delete(ROOT)
    if fs.exists(program..'.update-backup') then fs.delete(program..'.update-backup') end
  end)
  if not success then
    if not installed and original then pcall(function() local h=assert(fs.open(program,'w'));h.write(original);h.close() end) end
    if fs.exists(temp) then pcall(fs.delete,temp) end
    print(installed and 'Program updated; settings cleanup failed.' or 'Install failed; check program file before retrying.')
    return
  end
  print('Companion updated. Settings cleared.')
  print('Run companion to set up and pair again.')
end
if argv[1]=='remove' or argv[1]=='update' then
  local ok=pcall(maintenance)
  if not ok then print('Operation stopped. Check files before retrying.') end
  return
end
if not argv[1] or argv[1]=='help' then
  print('Mole Companion '..VERSION)
  print('companion start   Open turtle display')
  print('companion pair    Pair a turtle')
  print('companion update  Clean install')
  print('companion remove  Delete program/data')
  print('companion demo    Preview fake data')
  print('companion help    Show this guide')
  print('Start: arrows choose; R requests home')
  print('D: blocks  L: log  Q: close')
  return
end
if argv[1]~='start' and argv[1]~='pair' and argv[1]~='demo' then
  print('Unknown command. Use companion help.');return
end
local function readConfig(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,'r');if not h then return nil end
  local raw=h.readAll();h.close();local ok,v=pcall(textutils.unserialize,raw)
  if ok and type(v)=='table' and v.version==1 and type(v.pairs)=='table' then return v end
end
local config=readConfig(ROOT..'/config') or readConfig(ROOT..'/config.backup')
if not config and (fs.exists(ROOT..'/config') or fs.exists(ROOT..'/config.backup')) then
  print('Pairing file is damaged. Files kept.');print('Rename mole-companion-data, then retry.');return
end
config=config or {version=1,pairs={}}
local state=M.new(config.pairs)
local function save()
  fs.makeDir(ROOT);config.pairs=M.pairs(state)
  local h=assert(fs.open(ROOT..'/config.new','w'),'Cannot save companion settings');h.write(textutils.serialize(config));h.close()
  assert(readConfig(ROOT..'/config.new'),'Settings check failed')
  if fs.exists(ROOT..'/config') then
    if fs.exists(ROOT..'/config.backup') then fs.delete(ROOT..'/config.backup') end
    fs.move(ROOT..'/config',ROOT..'/config.backup')
  end
  fs.move(ROOT..'/config.new',ROOT..'/config')
end
local function question(prompt)
  write(prompt..' ');return read():match('^%s*(.-)%s*$')
end
local function choose(kind,predicate,prompt)
  while true do
    local choices={}
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,kind) then local p=peripheral.wrap(name);if not predicate or predicate(p) then choices[#choices+1]=name end end
    end
    table.sort(choices)
    if #choices==1 then return choices[1] end
    if #choices>1 then
      print('Choose a '..kind..':')
      for i,name in ipairs(choices) do print(i..' '..name) end
      local raw=question('Number, or q to exit:');if raw:lower()=='q' then return nil end
      local n=tonumber(raw);if n and choices[n] then return choices[n] end
    else
      print(prompt);print('Attach it, then press Enter to retry.')
      if question('Enter to retry, q to exit:'):lower()=='q' then return nil end
    end
  end
end
local function wireless(p) local ok,v=pcall(p.isWireless);return ok and v==true end
local monitorName,modemName,monitor
local function hardware()
  print('Mole Companion '..VERSION)
  print('Step 1/6: connect a monitor.')
  monitorName=choose('monitor',nil,'Place a monitor next to this computer.')
  if not monitorName then return false end
  monitor=peripheral.wrap(monitorName)
  if monitor.setTextScale then monitor.setTextScale(0.5) end
  monitor.clear();monitor.setCursorPos(1,1);monitor.write('Mole connected')
  print('Monitor connected: '..monitorName)
  print('Step 2/6: connect wireless modem.')
  modemName=choose('modem',wireless,'Connect a wireless or Ender modem. A wired modem cannot contact turtles.')
  if not modemName then return false end
  rednet.open(modemName)
  print('Modem connected. Station ID: '..os.getComputerID())
  print('Pairing needs companion-ready Mole.');print('Use companion demo to preview.')
  return true
end
if not hardware() then return end
local demo=argv[1]=='demo'
if demo then
  state=M.new({{id=21,name='Demo North',token='demo-only-token'},{id=22,name='Demo South',token='demo-only-token'}})
  for i,id in ipairs(state.order) do
    M.receive(state,id,{v=1,kind='status',session='demo',seq=1,token='demo-only-token',job='demo-job',phase=i==1 and 'Mining' or 'Waiting for fuel',y=18,depth=46,right=3,forward=7,fuel=1450,detail=i==2 and 'Refill the chest; use mole resume.' or nil},now())
    M.receive(state,id,{v=1,kind='log',session='demo',seq=1,token='demo-only-token',text='DEMO: simulated turtle; no real commands.'},now())
  end
  M.receive(state,21,{v=1,kind='discovery',session='demo',seq=1,token='demo-only-token',job='demo-job',block='examplemod:tin_ore',name='Tin ore',count=8},now())
end
local firstPairOffer=false
local pairOnly=argv[1]=='pair'
local pairComplete=false
local scroll=0
local returnNotice
local mode='log';local note='';local pairing;local confirmReturn;local pairConfirm;local hits={}
local function send(id,msg) if not demo then local ok,result=pcall(rednet.send,id,msg,PROTOCOL);return ok and result end;return false end
local function selected() return state.turtles[state.order[state.selected]] end
local function line(target,y,value,width)
  target.setCursorPos(1,y);target.write((text(value,512) or ''):sub(1,width))
end
local function display(target,isMonitor)
  local width,height=target.getSize();target.clear();hits={}
  if width<10 or height<6 then
    line(target,1,'Monitor too small.',width);if height>=2 then line(target,2,'Add monitor blocks.',width) end;return
  end
  if width<29 or height<12 then
    local t=selected();local rows={demo and 'Mole DEMO' or 'Mole Companion'}
    if pairing then
      rows={'Pair turtle','Station ID:',''..os.getComputerID(),'Pairing code:',pairing.code}
      if pairConfirm then rows[#rows+1]='Turtle #'..pairConfirm.id;rows[#rows+1]='Y=yes N=no'
      else rows[#rows+1]='mole companion';rows[#rows+1]='Choose 1 on';rows[#rows+1]='the turtle.' end
    elseif t then
      rows[#rows+1]=t.name..' #'..t.id
      rows[#rows+1]=t.awaitingMole and 'Waiting for Mole' or M.online(t,now()) and (t.status and t.status.phase or 'Connected') or 'No contact'
      if t.status then
        rows[#rows+1]=t.status.uncertain and 'Pos uncertain' or 'Y '..t.status.y..' D '..t.status.depth
        rows[#rows+1]='Fuel '..t.status.fuel
      end
      if t.command then rows[#rows+1]='Return '..t.command.result end
      local content={}
      if mode=='blocks' then
        local ids={};for id in pairs(t.blocks) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do for _,part in ipairs(M.wrap(id..' x'..t.blocks[id].count,width)) do content[#content+1]=part end end
      else for _,entry in ipairs(t.logs) do for _,part in ipairs(M.wrap(entry,width)) do content[#content+1]=part end end end
      local room=math.max(0,height-1-#rows);local finish=math.max(0,#content-scroll)
      for i=math.max(1,finish-room+1),finish do rows[#rows+1]=content[i] end
    else rows={'No turtles yet','companion pair','on the computer'} end
    if confirmReturn then rows={'Return turtle?','Y=yes on PC','Esc=cancel'} end
    for y=1,math.min(height-1,#rows) do line(target,y,rows[y],width) end
    line(target,height,'[<][>][R]',width)
    if isMonitor then hits={prev={1,3,height},next={4,6,height},returnHome={7,9,height}} end
    return
  end
  local t=selected();local rows={demo and 'MOLE COMPANION - DEMO' or 'MOLE COMPANION'}
  if pairing then
    rows[#rows+1]=pairConfirm and 'Step 5/6: confirm your turtle' or 'Step 3-4/6: prepare the turtle'
    rows[#rows+1]='STATION COMPUTER ID: '..os.getComputerID()
    rows[#rows+1]='PAIRING CODE: '..pairing.code
    rows[#rows+1]='Time left: '..math.max(0,math.ceil(pairing.expires-now()))..' seconds'
    if pairConfirm then
      rows[#rows+1]='Turtle #'..pairConfirm.id..': '..pairConfirm.name
      rows[#rows+1]='Is this yours? Y=yes N=no Esc=cancel'
    else
      rows[#rows+1]='Turtle: keep pickaxe + wireless modem'
      rows[#rows+1]='Run mole companion; choose 1.'
      rows[#rows+1]='Enter ID + code above. Esc: cancel'
    end
  elseif t then
    rows[#rows+1]=state.selected..'/'..#state.order..' '..t.name..' (#'..t.id..')'
    local age=t.lastSeen and math.max(0,math.floor(now()-t.lastSeen))
    rows[#rows+1]=t.awaitingMole and 'Paired - waiting for Mole to run' or M.online(t,now()) and 'Connected - '..(t.status and t.status.phase or 'Awaiting status') or 'No recent contact - '..(age and age..'s ago' or 'no report yet')
    if t.awaitingMole then rows[#rows+1]='Last connection check: '..(age or 0)..'s ago' end
    if t.status then
      local fresh=t.statusAt and now()-t.statusAt<=15
      rows[#rows+1]=t.status.uncertain and 'Position uncertain; recovering.' or (fresh and 'Y ' or 'Last Y ')..t.status.y..' | Depth '..t.status.depth
      rows[#rows+1]='Right '..t.status.right..' | Forward '..t.status.forward
      rows[#rows+1]=(fresh and 'Fuel: ' or 'Last fuel: ')..t.status.fuel
      if t.status.progress then rows[#rows+1]=t.status.progress end
    end
    if t.command then rows[#rows+1]='Return: '..t.command.result end
  else
    rows[#rows+1]='No paired turtles yet.'
    rows[#rows+1]=firstPairOffer and 'Pair now? Y=yes N=later' or 'Use companion pair, or press P.'
    rows[#rows+1]='Keep it nearby with a wireless modem.'
  end
  local content={}
  if t and not pairing then
    if mode=='blocks' then
      local ids={};for id in pairs(t.blocks) do ids[#ids+1]=id end;table.sort(ids)
      for _,id in ipairs(ids) do local b=t.blocks[id];content[#content+1]=(b.name or id)..' x'..b.count;if b.name then content[#content+1]=id end end
      if #content==0 then content={'No unfamiliar blocks reported.'} end
    else
      if t.status and t.status.detail then content[#content+1]=t.status.detail end
      for _,entry in ipairs(t.logs) do content[#content+1]=entry end
    end
  end
  local expanded={}
  for _,v in ipairs(content) do for _,piece in ipairs(M.wrap(v,width)) do expanded[#expanded+1]=piece end end
  local y=1
  for _,v in ipairs(rows) do if y<=height-3 then line(target,y,v,width);y=y+1 end end
  local available=height-2-y
  scroll=math.min(scroll,math.max(0,#expanded-available))
  local finish=math.max(0,#expanded-scroll)
  local first=math.max(1,finish-available+1)
  for i=first,finish do if y<height-2 then line(target,y,expanded[i],width);y=y+1 end end
  local notice=note
  if returnNotice and t and t.id==returnNotice.turtle and t.command and t.command.id==returnNotice.request then notice=M.returnNotice(t.command) end
  line(target,height-2,confirmReturn and 'Return selected turtle? Y=yes Esc=no' or notice,width)
  line(target,height-1,'[Prev] [Next] [Return]',width)
  line(target,height,'D: blocks L: log Up/Down: scroll Q: exit',width)
  if isMonitor then hits={prev={1,6,height-1},next={8,13,height-1},returnHome={15,22,height-1}} end
end
local function render()
  local ok=peripheral.isPresent(monitorName) and pcall(display,monitor,true)
  if not ok then note='Monitor disconnected. Reattach it.' end
  -- Monitor drawing never redirects the computer terminal.
  display(term,false)
  -- display(term) cleared hit positions; recreate from monitor dimensions.
  if ok then
    local w,h=monitor.getSize()
    hits=(w<29 or h<12) and {prev={1,3,h},next={4,6,h},returnHome={7,9,h},pair={10,12,h}}
      or {prev={1,6,h-1},next={8,13,h-1},returnHome={15,22,h-1},pair={24,29,h-1}}
  end
end
local function pairStart()
  if demo then note='Demo only. Exit to pair real turtles.';return end
  firstPairOffer=false;returnNotice=nil
  pairing={code=tostring(math.random(100000,999999)),expires=now()+300};pairConfirm=nil;confirmReturn=nil
  note='Pairing open for five minutes.'
end
local function action(which)
  confirmReturn=nil;scroll=0;returnNotice=nil;note=''
  if which=='prev' and #state.order>0 then state.selected=(state.selected-2)%#state.order+1
  elseif which=='next' and #state.order>0 then state.selected=state.selected%#state.order+1
  elseif which=='pair' then pairStart()
  elseif which=='returnHome' then
    if demo then note='Demo: return commands are disabled.'
    elseif selected() then confirmReturn=selected().id else note='Pair a turtle first.' end
  end
end
if not demo then save() end
if pairOnly then pairStart() end
local timer=os.startTimer(1);render()
while true do
  local event,a,b,c=os.pullEvent()
  if event=='char' then
    local key=a:lower()
    if key=='q' then break
    elseif key=='p' or key=='y' and firstPairOffer then pairStart()
    elseif key=='n' and firstPairOffer then firstPairOffer=false
    elseif key=='n' and pairing and pairConfirm then pairConfirm=nil;note='Keep the correct turtle nearby; retry.'
    elseif key=='d' then mode='blocks';scroll=0
    elseif key=='l' then mode='log';scroll=0
    elseif key=='r' then action('returnHome')
    elseif key=='y' and pairing and pairConfirm then
      print('Step 6/6: choose a turtle name.')
      print('Current name: '..pairConfirm.name)
      local name=question('Name (Enter keeps current):')
      if name~='' then pairConfirm.name=text(name,32) end
      local token=tostring(math.random(100000000,999999999))..'-'..tostring(os.epoch('utc'))
      if M.repair(state,pairConfirm.id,pairConfirm.name,token) then
        local packet={v=1,kind='paired',code=pairing.code,token=token,station=os.getComputerID()}
        save();send(pairConfirm.id,packet)
        state.turtles[pairConfirm.id].welcome={packet=packet,sent=now(),expires=now()+30}
        note='Pairing sent; waiting for turtle check.'
      else note='Already paired or station is full.' end
      pairing=nil;pairConfirm=nil
    elseif key=='y' and confirmReturn then
      local packet,why=M.command(state,confirmReturn,now())
      if packet then send(confirmReturn,packet);returnNotice={turtle=confirmReturn,request=packet.request};note='' else note=why end
      confirmReturn=nil
    end
  elseif event=='key' then
    if a==keys.left then action('prev') elseif a==keys.right or a==keys.tab then action('next')
    elseif a==keys.up then scroll=scroll+3 elseif a==keys.down then scroll=math.max(0,scroll-3)
    elseif a==keys.escape then pairing=nil;pairConfirm=nil;confirmReturn=nil;note='Cancelled.';if pairOnly then break end end
  elseif event=='monitor_touch' and a==monitorName then
    for name,hit in pairs(hits) do if b>=hit[1] and b<=hit[2] and c==hit[3] then action(name);break end end
  elseif event=='rednet_message' and c==PROTOCOL and not demo then
    if pairing and now()<pairing.expires and type(b)=='table' and b.v==1 and b.kind=='pair_hello' and b.code==pairing.code and b.wireless==true and integer(a) and a>=0 then
      if not pairConfirm then pairConfirm={id=a,name=text(b.name,32) or 'Turtle '..a} end
    else
      local reply=M.control(state,a,b,now())
      if reply then send(a,reply);if b.kind=='pair_ready' then note='Connection checked. Pairing complete.';pairComplete=true;if pairOnly then render();break end end
      else M.receive(state,a,b,now()) end
    end
  elseif event=='timer' and a==timer then
    if pairing and now()>=pairing.expires then pairing=nil;pairConfirm=nil;note='No completed pairing. Keep turtle nearby; press P to retry.' end
    if peripheral.isPresent(monitorName) then monitor=peripheral.wrap(monitorName);if monitor.setTextScale then monitor.setTextScale(0.5) end end
    if peripheral.isPresent(modemName) then pcall(rednet.open,modemName) end
    M.tick(state,now(),send)
    if demo then for _,id in ipairs(state.order) do state.turtles[id].lastSeen=now() end end
    timer=os.startTimer(1)
  elseif event=='peripheral' or event=='peripheral_detach' then
    if peripheral.isPresent(monitorName) then monitor=peripheral.wrap(monitorName);if monitor.setTextScale then monitor.setTextScale(0.5) end end
    if peripheral.isPresent(modemName) then pcall(rednet.open,modemName) else note='Modem disconnected. Reattach it.' end
  end
  render()
end
term.clear();term.setCursorPos(1,1);if pairOnly then
  print(pairComplete and 'Connection checked. Pairing complete.' or 'Pairing setup closed.')
  print('Use companion start for the display.')
else print('Companion closed. Turtles keep working.') end
