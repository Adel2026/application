/**
 * Auto Publisher Script for Edu Academy
 * Handles 100% of the build, upload, and OTA publishing pipeline automatically
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const https = require('https');

const targetApp = process.argv[2] || 'student'; // 'student' or 'teacher'
const releaseNotes = process.argv[3] || '• تحديثات وإصلاحات جديدة\n• تحسين الأداء والاستقرار';

const rootDir = path.resolve(__dirname, '..');
const appDir = targetApp === 'student'
  ? path.join(rootDir, 'student_app')
  : path.join(rootDir, 'flutter_app');

console.log(`🚀 Starting 100% Automated OTA Release Pipeline for: [${targetApp.toUpperCase()}]`);

// 1. Read & Bump pubspec.yaml
const pubspecPath = path.join(appDir, 'pubspec.yaml');
let pubspec = fs.readFileSync(pubspecPath, 'utf8');

const versionMatch = pubspec.match(/version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)/);
if (!versionMatch) {
  console.error('❌ Could not parse version in pubspec.yaml');
  process.exit(1);
}

const currentVersionName = versionMatch[1];
const currentVersionCode = parseInt(versionMatch[2], 10);
const newVersionCode = currentVersionCode + 1;

// Bump minor version
const vParts = currentVersionName.split('.').map(Number);
vParts[2] += 1;
const newVersionName = vParts.join('.');

console.log(`📦 Bumping Version: ${currentVersionName}+${currentVersionCode} ➔ ${newVersionName}+${newVersionCode}`);

pubspec = pubspec.replace(
  /version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/,
  `version: ${newVersionName}+${newVersionCode}`
);
fs.writeFileSync(pubspecPath, pubspec, 'utf8');

// 2. Build Universal Release APK (supports 100% of Android devices including 32-bit & 64-bit)
console.log('⚙️ Building Universal Flutter Release APK... (Compatible with all devices)');
execSync('flutter build apk --release', {
  cwd: appDir,
  stdio: 'inherit'
});

let builtApkPath = path.join(appDir, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
if (!fs.existsSync(builtApkPath)) {
  builtApkPath = path.join(appDir, 'build', 'app', 'outputs', 'flutter-apk', 'app-arm64-v8a-release.apk');
}
if (!fs.existsSync(builtApkPath)) {
  console.error('❌ APK build failed or file not found!');
  process.exit(1);
}

const releasesDir = path.join(rootDir, '..', 'Releases');
if (!fs.existsSync(releasesDir)) fs.mkdirSync(releasesDir, { recursive: true });

const targetApkName = `${targetApp}-app-v${newVersionName}.apk`;
const copiedApkPath = path.join(releasesDir, targetApkName);
fs.copyFileSync(builtApkPath, copiedApkPath);
console.log(`✅ Release APK ready at: ${copiedApkPath}`);

// 3. Upload to High-Speed Direct Cloud Hosting
console.log('☁️ Uploading APK to direct download cloud hosting...');
let downloadUrl = '';

// Try Catbox first (guaranteed 100% direct binary stream without web redirects)
try {
  const catboxCmd = `curl.exe -s -F "reqtype=fileupload" -F "fileToUpload=@${copiedApkPath}" https://catbox.moe/user/api.php`;
  const catboxRes = execSync(catboxCmd).toString().trim();
  if (catboxRes.startsWith('http')) downloadUrl = catboxRes;
} catch (e) {
  console.log('⚠️ Catbox upload failed, trying secondary host...');
}

// Fallback to tmpfiles if catbox fails
if (!downloadUrl) {
  try {
    const tmpCmd = `curl.exe -s -F "file=@${copiedApkPath}" https://tmpfiles.org/api/v1/upload`;
    const tmpRes = JSON.parse(execSync(tmpCmd).toString());
    if (tmpRes.status === 'success' && tmpRes.data && tmpRes.data.url) {
      downloadUrl = tmpRes.data.url.replace('tmpfiles.org/', 'tmpfiles.org/dl/');
    }
  } catch (e) {}
}

if (!downloadUrl || !downloadUrl.startsWith('http')) {
  console.error('❌ Upload failed! Could not obtain download URL.');
  process.exit(1);
}
console.log(`📡 APK uploaded successfully! Direct download URL: ${downloadUrl}`);

console.log(`🎉 APK uploaded successfully! Direct download URL: ${downloadUrl}`);

// 4. Update Firestore OTA Config Document
console.log('📡 Updating Firestore OTA document...');
const apiKey = 'AIzaSyBpi80cW_XpR7Jcx15zypKqn1qSdvFb3ws';
const projectId = 'edu-academy-hub';
const docName = targetApp === 'student' ? 'student_app_version' : 'teacher_app_version';

const body = JSON.stringify({
  fields: {
    latest_version_name: { stringValue: newVersionName },
    latest_version_code: { integerValue: String(newVersionCode) },
    download_url: { stringValue: downloadUrl },
    release_notes: { stringValue: releaseNotes },
    is_mandatory: { booleanValue: false }
  }
});

const options = {
  hostname: 'firestore.googleapis.com',
  path: `/v1/projects/${projectId}/databases/(default)/documents/academies/default/system_config/${docName}?key=${apiKey}`,
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
    if (res.statusCode === 200) {
      console.log('=====================================================');
      console.log(`✅ SUCCESS! [${targetApp.toUpperCase()}] v${newVersionName} is now LIVE!`);
      console.log(`📲 All devices will automatically get the update notification now!`);
      console.log('=====================================================');
    } else {
      console.error('❌ Failed to update Firestore:', data);
    }
  });
});

req.on('error', (e) => {
  console.error('❌ Request error:', e);
});

req.write(body);
req.end();
