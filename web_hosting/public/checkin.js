(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const sessionId = params.get('sessionId') || '', token = params.get('token') || '';
  let lesson = null, identity = null, credential = '', busy = false, done = false, generation = 0;
  let googleMode = !params.get('mode')?.startsWith('student-code');
  const code = () => $('student-code').value.trim().toUpperCase();
  const valid = () => lesson && (googleMode ? !!identity : /^[A-Z0-9]{5,20}$/.test(code())) && $('presence').checked && (!lesson.secretEnabled || /^\d{6}$/.test($('secret').value.trim()));
  const update = () => { $('submit').disabled = busy || done || !valid(); $('switch-mode').disabled = busy || done; $('switch-account').disabled = busy || done; };
  const message = value => { $('message').textContent = value; };
  async function request(action, data = {}) {
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 30000);
    try {
      const response = await fetch(window.FAP_CONFIG.appsScriptUrl, {
        method: 'POST', headers: {'Content-Type':'text/plain;charset=UTF-8'},
        body: JSON.stringify({action, sessionId, token, ...(googleMode && credential ? {idToken: credential} : {}), ...data}), signal: controller.signal
      });
      if (!response.ok) throw new Error('Không kết nối được máy chủ. Vui lòng thử lại.');
      let result;
      try { result = await response.json(); } catch { throw new Error('Máy chủ trả dữ liệu không hợp lệ. Liên hệ giảng viên.'); }
      if (!result.ok) {
        if (/Cần đăng nhập Google|Tài khoản Google không được phép/.test(result.error || '')) throw new Error('Máy chủ chưa cập nhật API sinh viên. Giảng viên cần triển khai Apps Script phiên bản mới.');
        throw new Error(result.error || 'Không thực hiện được yêu cầu.');
      }
      return result.data;
    } catch (error) {
      if (error.name === 'AbortError') throw new Error('Kết nối quá thời gian chờ. Hãy thử lại.');
      if (error instanceof TypeError) throw new Error('Không tải được dữ liệu. Kiểm tra kết nối mạng và thử lại.');
      throw error;
    } finally { clearTimeout(timer); }
  }
  function showLesson(value) {
    lesson = value;
    $('course').textContent = (lesson.subjectName || lesson.subjectCode) + ' · ' + lesson.classCode;
    $('date').textContent = lesson.date.split('-').reverse().join('/');
    $('slot').textContent = lesson.slot; $('time').textContent = lesson.startTime + ' – ' + lesson.endTime;
    $('secret-field').hidden = !lesson.secretEnabled; $('secret').required = !!lesson.secretEnabled;
    $('code-field').hidden = googleMode; $('student-code').required = !googleMode;
    $('lesson').hidden = false; $('presence').checked = false; $('secret').value = '';
  }
  async function load() {
    if (busy || done) return;
    if (!sessionId || !token) { message('Hãy quét mã QR đang hiển thị trên ứng dụng của giảng viên.'); return; }
    $('authentication').hidden = false;
    $('switch-mode').textContent = googleMode ? 'Dùng MSSV' : 'Đăng nhập Google thay cho MSSV';
    $('google-button').hidden = !googleMode; $('login-hint').hidden = !googleMode;
    if (googleMode && !credential) { $('lesson').hidden = true; message('Đăng nhập Google để kiểm tra buổi học.'); update(); return; }
    const current = ++generation;
    busy = true; lesson = null; $('lesson').hidden = true; $('retry').hidden = true; update(); message('Đang kiểm tra buổi học…');
    try {
      const info = await request(googleMode ? 'studentSessionInfo' : 'studentCodeSessionInfo');
      if (current !== generation) return;
      if (!info?.session || (!googleMode && info.checkInMode !== 'student-code-v2')) throw new Error('Máy chủ chưa cập nhật luồng điểm danh. Liên hệ giảng viên.');
      if (googleMode) {
        if (!info.student) throw new Error('Không xác minh được sinh viên. Đăng nhập lại.');
        identity = info.student;
        $('welcome').textContent = 'Xin chào, ' + identity.fullName;
        $('email').textContent = identity.studentCode + ' · ' + identity.email;
        $('identity').hidden = false; $('google-button').hidden = true; $('login-hint').hidden = true;
      }
      showLesson(info.session); message('');
    } catch (error) { if (current === generation) { message(error.message); $('retry').hidden = false; } }
    finally { if (current === generation) { busy = false; update(); } }
  }
  async function login(response) {
    if (busy || done || !googleMode) return;
    if (!response?.credential) { message('Google chưa trả thông tin đăng nhập. Hãy thử lại trong Chrome/Safari.'); return; }
    credential = response.credential; identity = null; await load();
  }
  $('switch-mode').addEventListener('click', () => {
    if (busy || done) return;
    generation++; googleMode = !googleMode; credential = ''; identity = null; lesson = null;
    $('identity').hidden = true; $('lesson').hidden = true; load();
  });
  $('switch-account').addEventListener('click', () => {
    if (busy || done) return;
    generation++; credential = ''; identity = null; lesson = null;
    $('identity').hidden = true; $('lesson').hidden = true;
    window.google?.accounts?.id?.disableAutoSelect(); load();
  });
  $('copy-link').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(location.href); $('browser-help').textContent = 'Đã sao chép. Mở Chrome/Safari và dán liên kết vào thanh địa chỉ.'; }
    catch { $('browser-help').textContent = 'Hãy sao chép liên kết từ thanh địa chỉ, rồi mở bằng Chrome/Safari.'; }
  });
  $('student-code').addEventListener('input', update);
  $('secret').addEventListener('input', update);
  $('presence').addEventListener('change', update);
  $('retry').addEventListener('click', load);
  $('checkin-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || done || !valid()) return;
    const current = generation;
    busy = true; update(); message('Đang ghi nhận điểm danh…');
    try {
      const receipt = await request(googleMode ? 'studentCheckIn' : 'studentCodeCheckIn', {
        ...(!googleMode ? {studentCode: code()} : {}), confirmPresent: true,
        useSecret: !!lesson.secretEnabled, secretCode: lesson.secretEnabled ? $('secret').value.trim() : ''});
      if (current !== generation) return;
      done = true; $('lesson').hidden = true; $('authentication').hidden = true; $('success').hidden = false;
      $('receipt').textContent = receipt.fullName + ' · ' + receipt.studentCode + ' · ' + lesson.classCode + ' · Slot ' + lesson.slot + ' · ' + lesson.date;
      credential = ''; message('');
    } catch (error) { if (current === generation) message(error.message); }
    finally { if (current === generation) { busy = false; update(); } }
  });
  if (sessionId && token) {
    const started = Date.now();
    const ready = setInterval(() => {
      if (window.google?.accounts?.id && window.FAP_CONFIG?.googleWebClientId) {
        clearInterval(ready);
        try {
          google.accounts.id.initialize({client_id: window.FAP_CONFIG.googleWebClientId,
            callback: login, ux_mode: 'popup', auto_select: false, use_fedcm_for_button: false});
          google.accounts.id.renderButton($('google-button'), {theme:'outline',size:'large',text:'signin_with',width:280});
          $('login-hint').textContent = 'Sử dụng Google email trường có trong danh sách lớp. Sau đăng nhập, buổi học hiển thị ngay tại đây.';
        } catch { $('login-hint').textContent = 'Không khởi tạo được Google. Mở liên kết trong Chrome/Safari hoặc dùng MSSV.'; }
      } else if (Date.now() - started > 15000) {
        clearInterval(ready); $('login-hint').textContent = 'Chưa tải được Google. Mở liên kết trong Chrome/Safari hoặc dùng MSSV.';
      }
    }, 150);
  }
  load();
})();
