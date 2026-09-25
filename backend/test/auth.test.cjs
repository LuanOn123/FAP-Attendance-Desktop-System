const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../apps_script/Code.gs'), 'utf8');

function fixture(overrides = {}, googleStatus = 200) {
  const claims = {aud:'web-client',iss:'https://accounts.google.com',exp:Date.now()/1000+3600,
    email_verified:true,email:'student@fpt.edu.vn',hd:'fpt.edu.vn',...overrides};
  const rows = {
    Students:[['studentId','studentCode','fullName','schoolEmail'],['s1','SE123456','Student','student@fpt.edu.vn']],
    Lecturers:[['lecturerId','lecturerCode','fullName','email','department'],['l1','GV01','Teacher','teacher@fpt.edu.vn','SE']],
    Sessions:[['sessionId','classId','date','slot','startTime','endTime','status','currentToken','tokenExpiredAt','createdBy'],
      ['session1','class1','2026-09-25','4','15:00','17:15','OPEN','qr',new Date(Date.now()+120000).toISOString(),'l1']],
    Enrollments:[['enrollmentId','classId','studentId'],['e1','class1','s1']],
    Classes:[['classId','semester','subjectCode','subjectName','classCode','lecturerId'],['class1','FA26','PRM393','Mobile','SE1928','l1']],
  };
  const properties = {SPREADSHEET_ID:'fixture',GOOGLE_CLIENT_ID:'desktop-client',GOOGLE_WEB_CLIENT_ID:'web-client',SCHOOL_DOMAINS:'fpt.edu.vn,fe.edu.vn'};
  let googleCalls = 0;
  const context = vm.createContext({
    PropertiesService:{getScriptProperties:()=>({getProperty:key=>properties[key]})},
    SpreadsheetApp:{openById:()=>({getSheetByName:name=>({getDataRange:()=>({getDisplayValues:()=>rows[name]})})})},
    UrlFetchApp:{fetch:()=>{googleCalls++;return {getResponseCode:()=>googleStatus,getContentText:()=>JSON.stringify(claims)};}},
    ContentService:{MimeType:{JSON:'json'},createTextOutput:text=>({setMimeType:()=>JSON.parse(text)})},
  });
  vm.runInContext(source,context);
  const call = (action='studentSessionInfo', extra={}) => context.doPost({postData:{contents:JSON.stringify({
    action,idToken:'synthetic-id-token-for-unit-test',sessionId:'session1',...extra,
  })}});
  return {call,rows,properties,googleCalls:()=>googleCalls};
}

test('TC01 student dispatch validates web token without requiring lecturer membership',()=>{
  const f=fixture(); const result=f.call();
  assert.equal(result.ok,true); assert.equal(result.data.student.studentCode,'SE123456');
  assert.equal(f.googleCalls(),1);
  assert.equal(result.data.accessToken,undefined);
});

for(const [label,claims,error] of [
  ['TC02 external domain',{email:'student@gmail.com',hd:undefined},/email trường/],
  ['TC06 wrong audience',{aud:'desktop-client'},/GOOGLE_WEB_CLIENT_ID/],
  ['TC07 expired token',{exp:0},/email trường/],
  ['invalid issuer',{iss:'https://attacker.example'},/email trường/],
  ['missing hd',{hd:undefined},/email trường/],
  ['wrong hd',{hd:'other.edu.vn'},/email trường/],
  ['unverified email',{email_verified:false},/email trường/],
  ['missing email_verified',{email_verified:undefined},/email trường/],
  ['unlisted school subdomain',{email:'student@student.fpt.edu.vn',hd:'student.fpt.edu.vn'},/email trường/],
]) test(label,()=>{const result=fixture(claims).call();assert.equal(result.ok,false);assert.match(result.error,error);});

test('email_verified accepts Google boolean and string true',()=>{
  for(const email_verified of [true,'true']) assert.equal(fixture({email_verified}).call().ok,true);
});

test('TC03 valid Google identity still requires exactly one pre-registered student',()=>{
  const missing=fixture({email:'missing@fpt.edu.vn'}).call(); assert.equal(missing.ok,false);assert.match(missing.error,/danh sách sinh viên/);
  const duplicate=fixture();duplicate.rows.Students.push(['s2','SE999999','Duplicate','student@fpt.edu.vn']);
  assert.match(duplicate.call().error,/bị trùng/);
});

test('enrollment and session status are separate from Google authentication',()=>{
  const f=fixture();f.rows.Enrollments.splice(1);assert.match(f.call().error,/không thuộc danh sách lớp/);
  const closed=fixture();closed.rows.Sessions[1][6]='CLOSED';assert.match(closed.call().error,/Phiên đã kết thúc/);
});

test('TC08 invalid Google token is rejected before student lookup',()=>{
  const f=fixture({},400);assert.match(f.call().error,/Phiên Google không hợp lệ/);assert.equal(f.googleCalls(),1);
  assert.match(f.call('studentSessionInfo',{idToken:''}).error,/đăng nhập email trường/);
  assert.equal(f.googleCalls(),1);
});

test('protected lecturer endpoint rejects web audience while desktop profile succeeds',()=>{
  assert.match(fixture().call('profile').error,/Tài khoản Google không được phép/);
  assert.equal(fixture({aud:'desktop-client',email:'teacher@fpt.edu.vn'}).call('profile').ok,true);
});

test('missing web audience reports server configuration instead of accepting token',()=>{
  const f=fixture(); delete f.properties.GOOGLE_WEB_CLIENT_ID;
  assert.match(f.call().error,/chưa cấu hình GOOGLE_WEB_CLIENT_ID/);
  assert.equal(f.googleCalls(),0);
});
