/* Shared Desktop/Mobile Lab 2. No Cloud Functions, scheduler, Firestore writes,
 * service-account keys or client-supplied roles. Existing Sheets are authoritative.
 * Add this file to the existing Desktop Apps Script project and call setupLab2Free.
 */
const LAB2_TABLES = Object.freeze({
  Lab2SessionMeta: ['sessionId','title','opensAt','closesAt','lateThresholdAt','eligibleStudentIds'],
  Lab2SharedArticles: ['id','classId','articleId','article','sharedBy','note','sharedAt'],
  Lab2ArticleCache: ['id','article','subjectIds','expiresAt'],
  Lab2Feeds: ['id','feed','expiresAt']
});
function setupLab2Free() {
  setupSheets(); // Existing owner's initializer only adds headers to completely empty tabs.
  const book = SpreadsheetApp.openById(config_().id);
  Object.keys(LAB2_TABLES).forEach(name => {
    const sheet = book.getSheetByName(name) || book.insertSheet(name);
    if (!sheet.getLastRow()) {
      sheet.getRange(1,1,1,LAB2_TABLES[name].length).setValues([LAB2_TABLES[name]]);
      sheet.setFrozenRows(1);
    }
    lab2Read_(book,name);
  });
  const health = lab2Health_();
  console.log(JSON.stringify(health));
  return health;
}
/** Owner-only editor check. Not exposed by doPost; prints counts, never roster or keys. */
function verifyLab2Free() {
  const book=SpreadsheetApp.openById(config_().id), tables={}, counts={};
  for(const name of ['Lecturers','Classes','Students','Enrollments','Sessions','Attendance','Lab2SessionMeta','Lab2SharedArticles']) {
    try { tables[name]=lab2Read_(book,name); counts[name]=tables[name].length; }
    catch(error) {
      console.log(JSON.stringify({schemaError:name,header:book.getSheetByName(name).getDataRange().getDisplayValues()[0]}));
      throw error;
    }
  }
  const cls=tables.Classes.find(c=>tables.Lecturers.some(l=>l.lecturerId===c.lecturerId));
  const news={};
  if(cls) {
    const lecturer=tables.Lecturers.find(l=>l.lecturerId===cls.lecturerId);
    const actor={role:'lecturer',entity:lecturer,uid:'lecturer-'+lecturer.lecturerId,email:lecturer.email};
    const snapshot=lab2SnapshotFrom_(tables,actor);
    counts.visibleClasses=snapshot.collections.classes.length;
    for(const source of ['OpenAlex','Crossref']) {
      try {const feed=lab2Discover_(book,actor,{subjectId:cls.subjectCode,source,page:1,sort:'recent'});
        news[source]={count:feed.articles.length,stale:feed.stale};}
      catch(error) {news[source]={error:error.message};}
    }
  }
  console.log(JSON.stringify({health:lab2Health_(),counts,news}));
}
function lab2Health_() {
  const p = PropertiesService.getScriptProperties();
  return {version: 'lab2-shared-sheets-v1', quizEnabled:false,
    firebaseProject:p.getProperty('LAB2_FIREBASE_PROJECT_ID') || 'fap-attendance-88920',
    authConfigured:!!p.getProperty('LAB2_FIREBASE_API_KEY'),
    openAlexConfigured:!!p.getProperty('OPENALEX_API_KEY')};
}
function lab2Read_(book,name) {
  if (!LAB2_TABLES[name]) return read_(book,name).rows;
  const sheet = book.getSheetByName(name);
  if (!sheet) throw Error('SHARED_BACKEND_SETUP_REQUIRED');
  const values = sheet.getDataRange().getDisplayValues(), header = LAB2_TABLES[name];
  if (JSON.stringify(values[0]) !== JSON.stringify(header)) throw Error('INVALID_SHEET_SCHEMA');
  const rows = values.slice(1).filter(r => r.some(v => v !== '')).map(r =>
    Object.fromEntries(header.map((h,i) => [h,r[i] || ''])));
  if (rows.some(r => !r[header[0]]) || new Set(rows.map(r => r[header[0]])).size !== rows.length)
    throw Error('INVALID_SHEET_IDS');
  return rows;
}
function lab2Hash_(text) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,text)
    .map(b => ('0'+((b+256)%256).toString(16)).slice(-2)).join('');
}
function lab2FirebaseIdentity_(token) {
  const p = PropertiesService.getScriptProperties();
  const key = p.getProperty('LAB2_FIREBASE_API_KEY');
  const project = p.getProperty('LAB2_FIREBASE_PROJECT_ID') || 'fap-attendance-88920';
  if (!key) throw Error('SHARED_BACKEND_SETUP_REQUIRED');
  if (typeof token !== 'string' || token.length > 10000 || token.split('.').length !== 3)
    throw Error('UNAUTHENTICATED');
  let claims;
  try { claims = JSON.parse(Utilities.newBlob(Utilities.base64DecodeWebSafe(token.split('.')[1])).getDataAsString()); }
  catch (_) { throw Error('UNAUTHENTICATED'); }
  if (claims.aud !== project || claims.iss !== 'https://securetoken.google.com/'+project ||
      !Number.isFinite(claims.exp) || claims.exp*1000 <= Date.now()) throw Error('UNAUTHENTICATED');
  const cache = CacheService.getScriptCache(), cacheKey = 'lab2auth:'+lab2Hash_(token);
  const cached = cache.get(cacheKey);
  if (cached) return JSON.parse(cached);
  // Google verifies the signature/token using this Firebase project's public API key.
  const response = UrlFetchApp.fetch('https://identitytoolkit.googleapis.com/v1/accounts:lookup?key='+encodeURIComponent(key), {
    method:'post', contentType:'application/json', payload:JSON.stringify({idToken:token}), muteHttpExceptions:true
  });
  if (response.getResponseCode() !== 200) throw Error('UNAUTHENTICATED');
  const users = JSON.parse(response.getContentText()).users || [];
  const user = users[0];
  if (users.length !== 1 || !user || user.localId !== claims.sub || user.disabled) throw Error('UNAUTHENTICATED');
  if (user.emailVerified !== true) throw Error('EMAIL_NOT_VERIFIED');
  const result = {firebaseUid:user.localId,email:String(user.email || '').trim().toLowerCase()};
  if (!result.email) throw Error('UNAUTHENTICATED');
  cache.put(cacheKey,JSON.stringify(result),Math.max(1,Math.min(60,Math.floor(claims.exp-Date.now()/1000))));
  return result;
}
function lab2Actor_(identity,cfg,book) {
  if (!cfg.domains.includes(identity.email.split('@')[1])) throw Error('PERMISSION_DENIED');
  const teachers = lab2Read_(book,'Lecturers').filter(r => String(r.email).trim().toLowerCase() === identity.email);
  if (teachers.length > 1) throw Error('DUPLICATE_PROFILE');
  if (teachers.length === 1) return {...identity,role:'lecturer',entity:teachers[0],uid:'lecturer-'+teachers[0].lecturerId};
  const students = lab2Read_(book,'Students').filter(r => String(r.schoolEmail).trim().toLowerCase() === identity.email);
  if (students.length !== 1) throw Error('PROFILE_NOT_REGISTERED');
  return {...identity,role:'student',entity:students[0],uid:'student-'+students[0].studentId};
}
function lab2Limit_(uid,action) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw Error('RATE_LIMITED');
  try {
    const cache = CacheService.getScriptCache(), key = 'lab2rate:'+lab2Hash_(uid+':'+action);
    const now = Date.now();
    let window = JSON.parse(cache.get(key) || 'null');
    if (!window || now-window.start >= 60000) window = {start:now,count:0};
    if (window.count >= (action === 'discoverArticles' ? 12 : 60)) throw Error('RATE_LIMITED');
    window.count++;
    cache.put(key,JSON.stringify(window),Math.max(1,Math.ceil((window.start+60000-now)/1000)));
  } finally { lock.releaseLock(); }
}
function lab2Class_(book,actor,id,teacherOnly) {
  const cls = lab2Read_(book,'Classes').find(c => c.classId === id);
  if (!cls) throw Error('PERMISSION_DENIED');
  if (actor.role === 'lecturer') {
    if (cls.lecturerId !== actor.entity.lecturerId) throw Error('PERMISSION_DENIED');
  } else if (teacherOnly || !lab2Read_(book,'Enrollments').some(e => e.classId === id && e.studentId === actor.entity.studentId)) {
    throw Error('NOT_ENROLLED');
  }
  return cls;
}
function lab2Write_(book,changes) {
  const requests = [], nextRows = {}, indexes = {}, capacities = {};
  for (const change of changes) {
    const header = LAB2_TABLES[change.table] || SCHEMA[change.table];
    if (!header) throw Error('INVALID_INPUT');
    const sheet = book.getSheetByName(change.table);
    if (!indexes[change.table]) {
      lab2Read_(book,change.table);
      const physicalRows=sheet.getDataRange().getDisplayValues().slice(1);
      indexes[change.table]=new Map(physicalRows.map((r,i)=>[r[0],i]));
      capacities[change.table]=sheet.getMaxRows();
    }
    const existing=indexes[change.table].get(String(change.row[header[0]]));
    const index=existing==null?-1:existing;
    const rowIndex = index < 0 ? (nextRows[change.table] || sheet.getLastRow()) : index+1;
    if (index < 0) nextRows[change.table] = rowIndex+1;
    if (index < 0) indexes[change.table].set(String(change.row[header[0]]),rowIndex-1);
    if (rowIndex+1 > capacities[change.table]) {
      requests.push({appendDimension:{sheetId:sheet.getSheetId(),dimension:'ROWS',length:rowIndex+1-capacities[change.table]}});
      capacities[change.table]=rowIndex+1;
    }
    requests.push({updateCells:{range:{sheetId:sheet.getSheetId(),startRowIndex:rowIndex,endRowIndex:rowIndex+1,
      startColumnIndex:0,endColumnIndex:header.length},rows:[{values:header.map(k =>
        ({userEnteredValue:{stringValue:String(change.row[k] == null ? '' : change.row[k])}}))}],fields:'userEnteredValue'}});
  }
  if (requests.length) Sheets.Spreadsheets.batchUpdate({requests},book.getId());
}
function lab2Millis_(date,time) {
  const value = Date.parse(String(date)+'T'+String(time || '00:00')+':00+07:00');
  if (!Number.isFinite(value)) throw Error('INVALID_SESSION_DATE');
  return value;
}
function lab2Meta_(book,session) {
  const stored = lab2Read_(book,'Lab2SessionMeta').find(m => m.sessionId === session.sessionId);
  if (stored) return {...stored,opensAt:Number(stored.opensAt),closesAt:Number(stored.closesAt),lateThresholdAt:Number(stored.lateThresholdAt),
    eligibleStudentIds:JSON.parse(stored.eligibleStudentIds)};
  // Desktop legacy sessions have no late threshold or historical membership snapshot.
  return {sessionId:session.sessionId,title:'Slot '+session.slot,opensAt:lab2Millis_(session.date,session.startTime),
    closesAt:lab2Millis_(session.date,session.endTime),lateThresholdAt:null,eligibleStudentIds:null};
}
function lab2Finalize_(book,session) {
  if (session.status !== 'OPEN') return;
  const meta = lab2Meta_(book,session);
  const eligible = meta.eligibleStudentIds || lab2Read_(book,'Enrollments').filter(e => e.classId === session.classId).map(e => e.studentId);
  if (eligible.length > 400) throw Error('CLASS_TOO_LARGE');
  const attendance = lab2Read_(book,'Attendance').filter(a => a.sessionId === session.sessionId);
  const now = new Date().toISOString();
  const changes = [{table:'Sessions',row:{...session,status:'CLOSED',currentToken:'',tokenExpiredAt:''}}];
  for (const id of new Set(eligible)) if (!attendance.some(a => a.studentId === id)) {
    changes.push({table:'Attendance',row:{attendanceId:Utilities.getUuid(),sessionId:session.sessionId,studentId:id,
      status:'ABSENT',checkInTime:'',updatedAt:now,note:'Lab2 finalized',updatedBy:session.createdBy}});
  }
  lab2Write_(book,changes);
}
function lab2SnapshotFrom_(tables,actor) {
  const classes = tables.Classes.filter(c => actor.role === 'lecturer' ? c.lecturerId === actor.entity.lecturerId :
    tables.Enrollments.some(e => e.classId === c.classId && e.studentId === actor.entity.studentId));
  const ids = new Set(classes.map(c => c.classId));
  const subjects = [...new Set(classes.map(c => c.subjectCode))];
  const c = {classes:[],subjects:subjects.map(id => ({id,code:id,name:classes.find(x=>x.subjectCode===id).subjectName,active:true})),
    classSessions:[],attendanceSessions:[],attendanceRecords:[],sharedArticles:[]};
  for (const cls of classes) {
    const students = tables.Students.filter(s => tables.Enrollments.some(e => e.classId===cls.classId && e.studentId===s.studentId));
    c.classes.push({id:cls.classId,classCode:cls.classCode,subjectId:cls.subjectCode,term:cls.semester,
      lecturerUids:['lecturer-'+cls.lecturerId],studentUids:actor.role==='lecturer'?students.map(s=>'student-'+s.studentId):[actor.uid],
      studentCount:students.length,status:'active'});
    c['classes/'+cls.classId+'/members'] = students.filter(s => actor.role==='lecturer'||s.studentId===actor.entity.studentId)
      .map(s=>({id:'student-'+s.studentId,studentUid:'student-'+s.studentId,studentCode:s.studentCode,displayName:s.fullName,active:true}));
  }
  for (const s of tables.Sessions.filter(s => ids.has(s.classId) && s.status !== 'RESET')) {
    const cls = classes.find(x => x.classId === s.classId);
    const records = tables.Attendance.filter(a => a.sessionId === s.sessionId);
    const raw = tables.Lab2SessionMeta.find(m => m.sessionId === s.sessionId);
    const eligible = raw ? JSON.parse(raw.eligibleStudentIds) : s.status==='CLOSED' ?
      [...new Set(records.map(a=>a.studentId))] : tables.Enrollments.filter(e=>e.classId===s.classId).map(e=>e.studentId);
    const opens = raw ? Number(raw.opensAt) : lab2Millis_(s.date,s.startTime);
    const closes = raw ? Number(raw.closesAt) : lab2Millis_(s.date,s.endTime);
    c.classSessions.push({id:s.sessionId,classId:s.classId,subjectId:cls.subjectCode,title:raw?raw.title:'Slot '+s.slot,
      lecturerUid:'lecturer-'+cls.lecturerId,startsAt:lab2Millis_(s.date,s.startTime),endsAt:lab2Millis_(s.date,s.endTime),
      status:s.status==='CLOSED'?'completed':'scheduled'});
    c.attendanceSessions.push({id:s.sessionId,classId:s.classId,classSessionId:s.sessionId,opensAt:opens,closesAt:closes,
      lateThresholdAt:raw?Number(raw.lateThresholdAt):null,status:s.status==='CLOSED'?'finalized':'open',
      eligibleStudentUids:eligible.filter(id=>actor.role==='lecturer'||id===actor.entity.studentId).map(id=>'student-'+id),
      membershipKnown:!!raw,qrRotationSeconds:120});
    for (const a of records.filter(a => actor.role==='lecturer'||a.studentId===actor.entity.studentId)) {
      if (!['PRESENT','LATE','ABSENT','EXCUSED'].includes(a.status)) continue;
      c.attendanceRecords.push({id:s.sessionId+'_student-'+a.studentId,classId:s.classId,classSessionId:s.sessionId,
        attendanceSessionId:s.sessionId,studentUid:'student-'+a.studentId,status:a.status.toLowerCase(),
        checkedInAt:a.checkInTime?Date.parse(a.checkInTime):null,recordedAt:Date.parse(a.updatedAt)||opens,notes:a.note||''});
    }
  }
  c.sharedArticles = tables.Lab2SharedArticles.filter(r=>ids.has(r.classId)).map(r=>
    ({...JSON.parse(r.article),id:r.id,classId:r.classId,articleId:r.articleId,sharedBy:r.sharedBy,note:r.note,sharedAt:Number(r.sharedAt)}));
  return {version:'lab2-shared-sheets-v1',syncedAt:Date.now(),profile:{uid:actor.uid,firebaseUid:actor.firebaseUid,
    displayName:actor.entity.fullName,email:actor.email,role:actor.role,active:true,subjectIds:subjects},collections:c};
}
function lab2Snapshot_(book,actor) {
  const tables = {};
  for (const name of ['Classes','Students','Enrollments','Sessions','Attendance','Lab2SessionMeta','Lab2SharedArticles']) tables[name]=lab2Read_(book,name);
  const allowed = new Set(tables.Classes.filter(c => actor.role==='lecturer' ? c.lecturerId===actor.entity.lecturerId :
    tables.Enrollments.some(e=>e.classId===c.classId&&e.studentId===actor.entity.studentId)).map(c=>c.classId));
  const expired = tables.Sessions.filter(s=>s.status==='OPEN'&&allowed.has(s.classId)&&
    tables.Lab2SessionMeta.some(m=>m.sessionId===s.sessionId&&Number(m.closesAt)<=Date.now()));
  if (expired.length) {
    const lock=LockService.getScriptLock();
    if(!lock.tryLock(15000)) throw Error('RATE_LIMITED');
    try {
      for(const old of expired) {
        const current=lab2Read_(book,'Sessions').find(s=>s.sessionId===old.sessionId);
        if(current&&current.status==='OPEN') lab2Finalize_(book,current);
      }
      tables.Sessions=lab2Read_(book,'Sessions');
      tables.Attendance=lab2Read_(book,'Attendance');
    } finally { lock.releaseLock(); }
  }
  return lab2SnapshotFrom_(tables,actor);
}
function lab2Mutate_(book,actor,name,d) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw Error('RATE_LIMITED');
  try {
    if (name==='createClassSession') {
      lab2Class_(book,actor,d.classId,true);
      const title=String(d.title||'').trim(), date=Utilities.formatDate(new Date(),'Asia/Ho_Chi_Minh','yyyy-MM-dd');
      const slot=String(d.slot||'1'), start=String(d.startTime||'08:00'), end=String(d.endTime||'09:30');
      const duration=Number(d.durationMinutes||10), late=Number(d.lateAfterMinutes==null?5:d.lateAfterMinutes);
      if (!title||title.length>150||! /^(?:[1-9]|1[0-2])$/.test(slot)||
          !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(start)||!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(end)||start>=end||
          !Number.isInteger(duration)||duration<1||duration>30||!Number.isInteger(late)||late<0||late>duration) throw Error('INVALID_INPUT');
      const existing=lab2Read_(book,'Sessions').filter(s=>s.classId===d.classId&&s.date===date&&s.slot===slot&&s.status!=='RESET');
      if (existing.length>1) throw Error('INVALID_SHEET_IDS');
      if (existing.length) { if(existing[0].status!=='OPEN') throw Error('SESSION_CLOSED'); return {classSessionId:existing[0].sessionId}; }
      const students=[...new Set(lab2Read_(book,'Enrollments').filter(e=>e.classId===d.classId).map(e=>e.studentId))];
      if(students.length>400) throw Error('CLASS_TOO_LARGE');
      const id=Utilities.getUuid(), now=Date.now();
      lab2Write_(book,[{table:'Sessions',row:{sessionId:id,classId:d.classId,date,slot,startTime:start,endTime:end,status:'OPEN',
        currentToken:Utilities.getUuid()+Utilities.getUuid(),tokenExpiredAt:new Date(now+120000).toISOString(),createdBy:actor.entity.lecturerId}},
        {table:'Lab2SessionMeta',row:{sessionId:id,title,opensAt:now,closesAt:now+duration*60000,
          lateThresholdAt:now+late*60000,eligibleStudentIds:JSON.stringify(students)}}]);
      return {classSessionId:id};
    }
    if(name==='checkInWithQr') {
      if(actor.role!=='student') throw Error('PERMISSION_DENIED');
      const text=String(d.token||'');
      if(text.length>2000) throw Error('QR_INVALID');
      const params={};
      text.replace(/[?&]([^=&]+)=([^&]*)/g,(_,k,v)=>{ params[decodeURIComponent(k)]=decodeURIComponent(v); return ''; });
      if(!params.sessionId||!params.token) throw Error('QR_INVALID');
      const s=lab2Read_(book,'Sessions').find(s=>s.sessionId===params.sessionId);
      if(!s) throw Error('QR_INVALID');
      lab2Class_(book,actor,s.classId,false);
      const meta=lab2Meta_(book,s), view=sessionView_(s), now=Date.now();
      if(s.status!=='OPEN'||now>=meta.closesAt) throw Error('SESSION_CLOSED');
      if(meta.eligibleStudentIds&&!meta.eligibleStudentIds.includes(actor.entity.studentId)) throw Error('NOT_ENROLLED');
      if(!Number.isFinite(Date.parse(s.tokenExpiredAt))||now>=Date.parse(s.tokenExpiredAt)) throw Error('QR_EXPIRED');
      if(!view.currentToken||params.token!==view.currentToken) throw Error('QR_INVALID');
      if(view.currentSecretCode) {
        if(!d.secretCode) throw Error('SECRET_REQUIRED');
        if(String(d.secretCode).trim()!==view.currentSecretCode) throw Error('QR_INVALID');
      }
      if(lab2Read_(book,'Attendance').some(a=>a.sessionId===s.sessionId&&a.studentId===actor.entity.studentId)) throw Error('ALREADY_CHECKED_IN');
      const status=meta.lateThresholdAt!=null&&now>=meta.lateThresholdAt?'LATE':'PRESENT';
      lab2Write_(book,[{table:'Attendance',row:{attendanceId:Utilities.getUuid(),sessionId:s.sessionId,studentId:actor.entity.studentId,
        status,checkInTime:new Date(now).toISOString(),updatedAt:new Date(now).toISOString(),note:'Firebase verified; Mobile Lab2',updatedBy:actor.email}}]);
      return {status:status.toLowerCase(),checkedInAt:now};
    }
    const sessionId=d.attendanceSessionId||d.classSessionId;
    const s=lab2Read_(book,'Sessions').find(s=>s.sessionId===sessionId);
    if(!s) throw Error('PERMISSION_DENIED');
    lab2Class_(book,actor,s.classId,true);
    if(name==='closeAttendanceSession') { if(s.status==='RESET') throw Error('SESSION_CLOSED'); lab2Finalize_(book,s); return {closed:true}; }
    const meta=lab2Meta_(book,s), now=Date.now();
    if(s.status!=='OPEN'||now>=meta.closesAt) throw Error('SESSION_CLOSED');
    if(name==='openAttendanceSession') return {attendanceSessionId:s.sessionId};
    if(name==='getQrToken') {
      let view=sessionView_(s), expiry=Date.parse(s.tokenExpiredAt);
      if(!view.currentToken||!Number.isFinite(expiry)||now>=expiry) {
        expiry=Math.min(now+120000,meta.closesAt);
        const value=Utilities.getUuid()+Utilities.getUuid();
        lab2Write_(book,[{table:'Sessions',row:{...s,currentToken:value+(view.currentSecretCode?'#'+view.currentSecretCode:''),tokenExpiredAt:new Date(expiry).toISOString()}}]);
        view={...view,currentToken:value};
      }
      const base=PropertiesService.getScriptProperties().getProperty('LAB2_CHECKIN_URL')||'faplab2://attendance';
      return {token:base+(base.includes('?')?'&':'?')+'sessionId='+encodeURIComponent(s.sessionId)+'&token='+encodeURIComponent(view.currentToken)+
        (view.currentSecretCode?'&mode=student-code-secret':''),expiresAt:Math.min(expiry,meta.closesAt),serverNow:now};
    }
    throw Error('FEATURE_DISABLED');
  } finally { lock.releaseLock(); }
}
function lab2Discover_(book,actor,d) {
  const classes=lab2Read_(book,'Classes').filter(c=>c.subjectCode===d.subjectId);
  if(!classes.some(c=>actor.role==='lecturer'?c.lecturerId===actor.entity.lecturerId:
      lab2Read_(book,'Enrollments').some(e=>e.classId===c.classId&&e.studentId===actor.entity.studentId))) throw Error('PERMISSION_DENIED');
  const source=d.source, page=Number(d.page||1), sort=d.sort||'recent';
  if(!['OpenAlex','Crossref'].includes(source)||!['recent','relevance'].includes(sort)||!Number.isInteger(page)||page<1||page>50) throw Error('INVALID_INPUT');
  const keywords={PRM393:'Flutter Dart mobile development',PRN212:'ASP.NET Core',SWE201c:'software engineering'};
  const query=String(d.query||keywords[d.subjectId]||classes[0].subjectName).trim();
  if(!query||query.length>150||d.fromDate&&!/^\d{4}-\d{2}-\d{2}$/.test(d.fromDate)) throw Error('INVALID_INPUT');
  const hash=lab2Hash_(JSON.stringify([d.subjectId,source,query,page,sort,d.fromDate||'']));
  const cached=lab2Read_(book,'Lab2Feeds').find(r=>r.id===hash), now=Date.now();
  if(cached&&Number(cached.expiresAt)>now) return {...JSON.parse(cached.feed),cached:true,stale:false};
  const props=PropertiesService.getScriptProperties(), headers={};
  let url;
  if(source==='OpenAlex') {
    const key=props.getProperty('OPENALEX_API_KEY'); if(!key) throw Error('OPENALEX_SETUP_REQUIRED');
    headers.Authorization='Bearer '+key;
    url='https://api.openalex.org/works?search='+encodeURIComponent(query)+'&per_page=20&page='+page+
      '&sort='+(sort==='recent'?'publication_date:desc':'relevance_score:desc')+(d.fromDate?'&filter=from_publication_date:'+d.fromDate:'');
  } else {
    url='https://api.crossref.org/works?query='+encodeURIComponent(query)+'&rows=20&offset='+((page-1)*20)+
      '&sort='+(sort==='recent'?'published':'relevance')+'&order=desc'+(d.fromDate?'&filter=from-pub-date:'+d.fromDate:'');
  }
  try {
    const response=UrlFetchApp.fetch(url,{headers,muteHttpExceptions:true});
    if(response.getResponseCode()!==200) throw Error('ARTICLE_SOURCE_UNAVAILABLE');
    const json=JSON.parse(response.getContentText()), items=source==='OpenAlex'?json.results:json.message.items;
    const unique={};
    for(const item of items) {
      const doi=String(item.doi||item.DOI||'').replace(/^https?:\/\/(?:dx\.)?doi.org\//i,'').trim().toLowerCase();
      const rawUrl=doi?'https://doi.org/'+doi:source==='OpenAlex'?((item.primary_location||{}).landing_page_url||item.id):item.URL;
      const title=source==='OpenAlex'?item.display_name:(item.title||[])[0];
      if(!title||!/^https:\/\/[^\s@]+$/i.test(rawUrl||'')) continue;
      const id=lab2Hash_(doi||rawUrl);
      const parts=((item.published||item['published-print']||item['published-online']||{})['date-parts']||[])[0];
      const date=source==='OpenAlex'?item.publication_date:parts?parts.map((n,i)=>i?String(n).padStart(2,'0'):String(n)).join('-'):null;
      unique[id]={id,DOI:doi||null,title:String(title).slice(0,500),url:rawUrl,source,
        publisher:String(source==='OpenAlex'?(((item.primary_location||{}).source||{}).display_name||''):item.publisher||'').slice(0,200),
        authors:(source==='OpenAlex'?(item.authorships||[]).map(a=>(a.author||{}).display_name):(item.author||[]).map(a=>[a.given,a.family].filter(Boolean).join(' '))).filter(Boolean).slice(0,12),
        publishedAt:date,abstractSnippet:null,subjectIds:[d.subjectId]};
    }
    const articles=Object.values(unique), feed={articles,nextPage:items.length===20?page+1:null,fetchedAt:now,expiresAt:now+21600000};
    const lock=LockService.getScriptLock(); if(!lock.tryLock(15000)) throw Error('RATE_LIMITED');
    try {
      const previous=lab2Read_(book,'Lab2ArticleCache');
      if(previous.length>2000) throw Error('ARTICLE_CACHE_FULL');
      lab2Write_(book,[{table:'Lab2Feeds',row:{id:hash,feed:JSON.stringify(feed),expiresAt:feed.expiresAt}},...articles.map(a=>{
        const old=previous.find(r=>r.id===a.id); const subjects=[...new Set([...(old?JSON.parse(old.subjectIds):[]),d.subjectId])];
        return {table:'Lab2ArticleCache',row:{id:a.id,article:JSON.stringify(a),subjectIds:JSON.stringify(subjects),expiresAt:feed.expiresAt}};
      })]);
    } finally { lock.releaseLock(); }
    return {...feed,cached:false,stale:false};
  } catch(_) { if(cached) return {...JSON.parse(cached.feed),cached:true,stale:true}; throw Error('ARTICLE_SOURCE_UNAVAILABLE'); }
}
function lab2Share_(book,actor,d) {
  const cls=lab2Class_(book,actor,d.classId,true), note=String(d.note||'').trim();
  if(note.length>500) throw Error('INVALID_INPUT');
  const article=lab2Read_(book,'Lab2ArticleCache').find(a=>a.id===d.articleId&&JSON.parse(a.subjectIds).includes(cls.subjectCode));
  if(!article) throw Error('INVALID_INPUT');
  const lock=LockService.getScriptLock(); if(!lock.tryLock(15000)) throw Error('RATE_LIMITED');
  try { lab2Write_(book,[{table:'Lab2SharedArticles',row:{id:d.classId+'_'+article.id,classId:d.classId,
    articleId:article.id,article:article.article,sharedBy:actor.uid,note,sharedAt:Date.now()}}]); return {shared:true}; }
  finally { lock.releaseLock(); }
}
function lab2Handle_(request) {
  if(request.action==='lab2Health') return lab2Health_();
  const cfg=config_(), book=SpreadsheetApp.openById(cfg.id);
  const identity=lab2FirebaseIdentity_(request.idToken), actor=lab2Actor_(identity,cfg,book);
  const name=request.action==='lab2Snapshot'?'snapshot':request.name;
  lab2Limit_(actor.firebaseUid,name);
  if(name==='snapshot') return lab2Snapshot_(book,actor);
  const d=request.input;
  if(!d||typeof d!=='object'||Array.isArray(d)) throw Error('INVALID_INPUT');
  if(name==='discoverArticles') return lab2Discover_(book,actor,d);
  if(name==='shareArticle') return lab2Share_(book,actor,d);
  if(!['createClassSession','openAttendanceSession','getQrToken','checkInWithQr','closeAttendanceSession'].includes(name)) throw Error('FEATURE_DISABLED');
  return lab2Mutate_(book,actor,name,d);
}
