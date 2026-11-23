const https = require('https');

const apiKey = 'AIzaSyBpi80cW_XpR7Jcx15zypKqn1qSdvFb3ws';
const projectId = 'edu-academy-hub';

const body = JSON.stringify({
  fields: {
    latest_version_name: { stringValue: '1.0.3' },
    latest_version_code: { integerValue: '4' },
    download_url: { stringValue: 'https://files.catbox.moe/9dr984.apk' },
    release_notes: { stringValue: '• ميزة التحديث والتثبيت التلقائي الفوري من داخل التطبيق بدون متصفح 🚀\n• تحسين الأداء وتخفيض حجم التطبيق\n• إصلاحات شاملة' },
    is_mandatory: { booleanValue: false }
  }
});

const options = {
  hostname: 'firestore.googleapis.com',
  path: `/v1/projects/${projectId}/databases/(default)/documents/academies/default/system_config/student_app_version?key=${apiKey}`,
  method: 'PATCH',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body)
  }
};

const req = https.request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => {
    console.log('Status:', res.statusCode);
    console.log('Response:', data);
  });
});

req.on('error', (e) => {
  console.error('Error:', e);
});

req.write(body);
req.end();
