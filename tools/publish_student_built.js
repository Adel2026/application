const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const https = require('https');

const apkPath = path.resolve(__dirname, '..', 'student_app', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
console.log('Apk exists:', fs.existsSync(apkPath), 'Size:', fs.statSync(apkPath).size);

const releasesDir = path.resolve(__dirname, '..', '..', 'Releases');
if (!fs.existsSync(releasesDir)) fs.mkdirSync(releasesDir, { recursive: true });
const targetApk = path.join(releasesDir, 'student-app-v1.0.29.apk');
fs.copyFileSync(apkPath, targetApk);
console.log('Copied to:', targetApk);

console.log('Uploading to Catbox...');
let downloadUrl = '';
try {
  const curlCmd = `curl.exe -s -F "reqtype=fileupload" -F "fileToUpload=@${targetApk}" https://catbox.moe/user/api.php`;
  const catboxRes = execSync(curlCmd).toString().trim();
  if (catboxRes.startsWith('http')) downloadUrl = catboxRes;
} catch (e) {
  console.log('Catbox upload error:', e.message);
}

if (!downloadUrl) {
  console.log('Trying tmpfiles...');
  const tmpCmd = `curl.exe -s -F "file=@${targetApk}" https://tmpfiles.org/api/v1/upload`;
  const tmpRes = JSON.parse(execSync(tmpCmd).toString());
  downloadUrl = tmpRes.data.url.replace('tmpfiles.org/', 'tmpfiles.org/dl/');
}
console.log('Final Download URL:', downloadUrl);

const apiKey = 'AIzaSyBpi80cW_XpR7Jcx15zypKqn1qSdvFb3ws';
const projectId = 'edu-academy-hub';
const docName = 'student_app_version';

const body = JSON.stringify({
  fields: {
    latest_version_name: { stringValue: '1.0.29' },
    latest_version_code: { integerValue: '3011' },
    download_url: { stringValue: downloadUrl },
    release_notes: { stringValue: '• تفعيل شاشة الإعدادات والملف الشخصي المتطورة ⚙️\n• ربط مركز الإشعارات والتنبيهات المتقدم 📢\n• إمكانية تجربة أصوات التنبيهات وإدارة الأمان والتخزين' },
    is_mandatory: { booleanValue: false }
  }
});

const req = https.request({
  hostname: 'firestore.googleapis.com',
  path: `/v1/projects/${projectId}/databases/(default)/documents/academies/default/system_config/${docName}?key=${apiKey}`,
  method: 'PATCH',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body)
  }
}, (res) => {
  console.log('Firestore update status:', res.statusCode);
  console.log('Done!');
});
req.on('error', e => console.error('Error:', e));
req.write(body);
req.end();
