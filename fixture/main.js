const { app } = require('electron');
const { autoUpdater } = require('electron-updater');

app.whenReady().then(() => {
  console.log('RUNNING version', app.getVersion(), 'from', process.execPath);
  autoUpdater.forceDevUpdateConfig = false;
  autoUpdater.logger = console;
  // Flip to quitAndInstall(true, true) to exercise the isSilent:true / elevate.exe
  // path instead of the default wizard path -- see README.md "isSilent true vs false".
  autoUpdater.on('update-downloaded', () => autoUpdater.quitAndInstall());
  autoUpdater.checkForUpdates().catch(e => console.error('updater:', e.message));
});
