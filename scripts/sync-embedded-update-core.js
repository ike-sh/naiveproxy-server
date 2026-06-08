const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const installPath = path.join(root, 'install-naive-server.sh');
const corePath = path.join(root, 'lib', 'update-core.sh');

const coreBody = fs.readFileSync(corePath, 'utf8')
  .replace(/^#!.*\n/, '')
  .replace(/^# NaiveProxy Server.*\n\n/, '');

let s = fs.readFileSync(installPath, 'utf8');
const marker = "cat <<'NAIVE_EMBEDDED_UPDATE_CORE'";
const start = s.indexOf(marker);
const end = s.indexOf('\nNAIVE_EMBEDDED_UPDATE_CORE', start);
if (start < 0 || end < 0) {
  console.error('NAIVE_EMBEDDED_UPDATE_CORE markers not found');
  process.exit(1);
}
const before = s.slice(0, start + marker.length + 1);
const after = s.slice(end);
s = before + '\n' + coreBody + after;
fs.writeFileSync(installPath, s);
console.log('synced embedded update-core');
