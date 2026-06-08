const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const installPath = path.join(root, 'install-naive-server.sh');
const corePath = path.join(root, 'lib', 'update-core.sh');

let s = fs.readFileSync(installPath, 'utf8');
const start = s.indexOf('write_update_script() {');
const heredocStart = s.indexOf("    cat <<'UPDATE_BODY'", start);
const heredocEnd = s.indexOf('\nUPDATE_BODY', heredocStart);
if (heredocStart < 0 || heredocEnd < 0) {
  console.error('UPDATE_BODY markers not found');
  process.exit(1);
}
const endFunc = s.indexOf('write_env_file()', heredocEnd);

const coreBody = fs.readFileSync(corePath, 'utf8')
  .replace(/^#!.*\n/, '')
  .replace(/^# update core\n\n/, '');

const replacement = `_naive_cat_update_core() {
  local core_file="\${NAIVE_SCRIPT_DIR}/lib/update-core.sh"
  if [[ -n "\${NAIVE_SCRIPT_DIR:-}" && -f "\$core_file" ]]; then
    cat "\$core_file"
    return 0
  fi
  cat <<'NAIVE_EMBEDDED_UPDATE_CORE'
${coreBody}NAIVE_EMBEDDED_UPDATE_CORE
}

write_update_script() {
  backup_file "\$UPDATE_SCRIPT"
  {
    printf '#!/usr/bin/env bash\\n'
    printf 'set -euo pipefail\\n\\n'
    printf 'DEFAULT_REPO=%q\\n' "\$REPO"
    printf 'DEFAULT_INSTALL_BIN=%q\\n' "\$INSTALL_BIN"
    printf 'DEFAULT_SERVICE_NAME=%q\\n' "\$SERVICE_NAME"
    _naive_cat_update_core
  } > "\$UPDATE_SCRIPT"
  chmod 755 "\$UPDATE_SCRIPT"
  log_ok "更新脚本已写入：\$UPDATE_SCRIPT"
}

`;

s = s.slice(0, start) + replacement + s.slice(endFunc);
fs.writeFileSync(installPath, s);
console.log('patched install-naive-server.sh');
