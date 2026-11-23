const fs = require('fs');

for (const p of ['flutter_app/lib/screens/teacher_chat_screen.dart', 'student_app/lib/screens/tabs/chat_tab.dart']) {
  let c = fs.readFileSync(p, 'utf8');
  
  c = c.replace(
    /final res = await FilePicker\.pickFiles\(\);[\s\S]*?final fileName = res\.files\.single\.name;/,
    `final files = await FilePicker.pickFiles();
      if (files.isEmpty || files.first.path == null) return;

      final file = File(files.first.path!);
      final fileName = files.first.name;`
  );
  
  fs.writeFileSync(p, c, 'utf8');
}
console.log('Successfully updated FilePicker logic in both files.');
