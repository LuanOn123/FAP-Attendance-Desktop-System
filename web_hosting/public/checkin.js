(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const sessionId = params.get('sessionId') || '';
  const qrToken = params.get('token') || '';
  let credential = '', identity = null, lesson = null, busy = false, generation = 0;
  const message = text => { $('message').textContent = text; };
  const update = () => { $('submit').disabled = busy || !identity || !$('presence').checked || ($('use-secret').checked && !/^\d{6}$/.test($('secret').value.trim())); };
  async function request(action, data) {
    const response = await fetch(window.FAP_CONFIG.appsScriptUrl, {
      method: 'POST', headers: {'Content-Type': 'text/plain;charset=UTF-8'},
      body: JSON.stringify({action, sessionId, idToken: credential, ...data}), signal: AbortSignal.timeout(30000)
    });
    if (!response.ok) throw new Error('Không kết nối được máy chủ. Vui lòng thử lại.');
    const result = await response.json();
    if (!result.ok) throw new Error(result.error || 'Không thực hiện được yêu cầu.');
    return result.data;
  }
  async function login(response) {
    const current = ++generation;
    credential = response.credential;
    identity = null; lesson = null; $('lesson').hidden = true; $('success').hidden = true;
    $('presence').checked = false; busy = true; update(); message('Đang xác minh tài khoản và danh sách lớp…');
    try {
      const info = await request('studentSessionInfo', {});
      if (current !== generation) return;
      identity = info.student; lesson = info.session;
      $('welcome').textContent = 'Xin chào, ' + identity.fullName;
      $('email').textContent = identity.studentCode + ' · ' + identity.email;
      $('course').textContent = lesson.subjectCode + ' · ' + lesson.classCode;
      $('date').textContent = lesson.date.split('-').reverse().join('/');
      $('slot').textContent = lesson.slot;
      $('time').textContent = lesson.startTime + ' – ' + lesson.endTime;
      $('identity').hidden = false; $('lesson').hidden = false; $('google-button').hidden = true; $('login-hint').hidden = true;
      message('');
    } catch (error) { if (current === generation) { credential = ''; message(error.message); } }
    finally { if (current === generation) { busy = false; update(); } }
  }
  $('presence').addEventListener('change', update);
  $('secret').addEventListener('input', update);
  $('use-secret').addEventListener('change', () => { $('secret-field').hidden = !$('use-secret').checked; update(); });
  $('switch-account').addEventListener('click', () => {
    generation++; credential = ''; identity = null; lesson = null; busy = false;
    $('identity').hidden = true; $('lesson').hidden = true; $('google-button').hidden = false;
    $('presence').checked = false; $('secret').value = ''; $('use-secret').checked = false; $('secret-field').hidden = true;
    google.accounts.id.disableAutoSelect(); message(''); update();
  });
  $('checkin-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || !identity || !$('presence').checked) return;
    busy = true; update(); message('Đang ghi nhận điểm danh…');
    try {
      const receipt = await request('studentCheckIn', {token: qrToken, useSecret: $('use-secret').checked, secretCode: $('secret').value.trim(), confirmPresent: $('presence').checked});
      $('lesson').hidden = true; $('success').hidden = false;
      $('receipt').textContent = receipt.fullName + ' · ' + lesson.classCode + ' · Slot ' + lesson.slot + ' · ' + lesson.date + ' · ' + new Date(receipt.checkInTime).toLocaleTimeString('vi-VN', {timeZone: 'Asia/Ho_Chi_Minh'});
      credential = ''; identity = null; $('switch-account').hidden = true; message('');
    } catch (error) { message(error.message); }
    finally { busy = false; update(); }
  });
  if (!sessionId) { $('login-hint').textContent = 'Hãy quét mã QR do giảng viên đang hiển thị để mở đúng buổi học.'; return; }
  const started = Date.now();
  const ready = setInterval(() => {
    if (window.google?.accounts?.id && window.FAP_CONFIG?.googleWebClientId) {
      clearInterval(ready);
      google.accounts.id.initialize({client_id: window.FAP_CONFIG.googleWebClientId, callback: login, auto_select: false});
      google.accounts.id.renderButton($('google-button'), {theme: 'outline', size: 'large', text: 'signin_with', width: 280});
      $('login-hint').textContent = 'Sử dụng tài khoản Google email trường có trong danh sách lớp.';
    } else if (Date.now() - started > 15000) { clearInterval(ready); $('login-hint').textContent = 'Chưa tải được đăng nhập Google. Kiểm tra kết nối và tải lại trang.'; }
  }, 150);
})();
