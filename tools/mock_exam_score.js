const https = require('https');

const apiKey = 'AIzaSyBpi80cW_XpR7Jcx15zypKqn1qSdvFb3ws';
const projectId = 'edu-academy-hub';

// 1. Create/Update Exam in Firestore
const examBody = JSON.stringify({
  fields: {
    id: { stringValue: 'exam_demo_1' },
    title: { stringValue: 'اختبار نصف الفصل الدراسي - جبر وهندسة 📐' },
    max_score: { doubleValue: 50.0 },
    date: { stringValue: '2026-11-20' },
    exam_date: { stringValue: '2026-11-20' },
    group_id: { stringValue: '1' }
  }
});

function patchDoc(path, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${projectId}/databases/(default)/documents/${path}?key=${apiKey}`,
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, data }));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function run() {
  console.log('Pushing exam doc...');
  await patchDoc('academies/default/exams/exam_demo_1', examBody);

  console.log('Pushing score doc with real student details for Std-113...');
  const scoreBody = JSON.stringify({
    fields: {
      id: { stringValue: 'score_113_demo' },
      exam_id: { stringValue: 'exam_demo_1' },
      exam_title: { stringValue: 'اختبار نصف الفصل الدراسي - جبر وهندسة 📐' },
      exam_date: { stringValue: '2026-11-20' },
      student_id: { stringValue: 'Std-113' },
      student_name: { stringValue: 'إيلاريا جورج عادل' },
      student_code: { stringValue: '113' },
      group_name: { stringValue: 'مجموعة الصف الثالث الإعدادي' },
      grade: { stringValue: 'الصف الثالث الإعدادي' },
      teacher_name: { stringValue: 'أ/ عادل سليمان' },
      center_name: { stringValue: 'أكاديمية التفوق التعليمية' },
      score: { doubleValue: 49.5 },
      max_score: { doubleValue: 50.0 },
      percentage: { doubleValue: 99.0 },
      rank: { integerValue: '1' },
      has_certificate: { booleanValue: true },
      certificate_title: { stringValue: 'شهادة المركز الأول والصدارة 🏆' },
      notes: { stringValue: 'إجابة نموذجية فائقة التميز والإتقان! بارك الله فيك 🌟' }
    }
  });
  const res = await patchDoc('academies/default/exam_scores/score_113_demo', scoreBody);
  console.log('Score pushed for Std-113:', res.status);

  // Push official Notification to trigger student device notification
  console.log('Pushing certificate notification doc...');
  const notifBody = JSON.stringify({
    fields: {
      id: { stringValue: 'cert_exam_demo_1_Std-113' },
      title: { stringValue: '🎓 شهادة تقدير وتفوق جديدة!' },
      body: { stringValue: 'ألف مبروك يا إيلاريا جورج عادل! لقد حصلتِ على شهادة المركز الأول والصدارة 🏆 في "اختبار نصف الفصل الدراسي - جبر وهندسة" بدرجة 49.5 / 50 (%99.0) 🌟' },
      target_type: { stringValue: 'student' },
      target_id: { stringValue: 'Std-113' },
      type: { stringValue: 'certificate' },
      exam_id: { stringValue: 'exam_demo_1' },
      student_id: { stringValue: 'Std-113' }
    }
  });
  const notifRes = await patchDoc('academies/default/notifications/cert_exam_demo_1_Std-113', notifBody);
  console.log('Notification pushed:', notifRes.status);
}

run();
