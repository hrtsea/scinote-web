#!/usr/bin/env node

const { spawn, execSync } = require('child_process');
let enginePaths = [];
try {
  enginePaths = execSync('ls -d $PWD/addons/*').toString().split('\n').filter((p) => !!p);
} catch {
  console.log('No addons to install yarn packages for.');
}
enginePaths.forEach(enginePath => {
  spawn('yarn', ['install'], {
    env: process.env,
    cwd: enginePath,
    stdio: 'inherit'
  });
});
