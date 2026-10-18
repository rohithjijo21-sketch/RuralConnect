import { readFile, writeFile, mkdir } from 'node:fs/promises';
const apps = ['passenger', 'driver', 'bus'];
for (const name of apps) {
  const base = new URL('../apps/' + name + '/', import.meta.url),
    manifest = new URL('android/app/src/main/AndroidManifest.xml', base);
  try {
    let text = await readFile(manifest, 'utf8');
    const permissions = [
      'android.permission.INTERNET',
      ...(name === 'bus'
        ? ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION']
        : []),
    ];
    for (const permission of permissions)
      if (!text.includes(permission))
        text = text.replace(
          '<application',
          '<uses-permission android:name="' + permission + '"/>\n    <application',
        );
    await writeFile(manifest, text);
    const debug = new URL('android/app/src/debug/', base);
    await mkdir(debug, { recursive: true });
    await writeFile(
      new URL('AndroidManifest.xml', debug),
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools"><application android:usesCleartextTraffic="true" tools:replace="android:usesCleartextTraffic"/></manifest>\n',
    );
    if (name === 'bus') {
      const plist = new URL('ios/Runner/Info.plist', base);
      text = await readFile(plist, 'utf8');
      if (!text.includes('NSLocationWhenInUseUsageDescription'))
        text = text.replace(
          '</dict>',
          '<key>NSLocationWhenInUseUsageDescription</key><string>Share this bus position with passengers only while an assigned service is active and the app is in the foreground.</string>\n</dict>',
        );
      await writeFile(plist, text);
    }
  } catch (error) {
    throw Error(name + ': generate native targets before configuration (' + error.message + ')');
  }
}
console.log(
  'Configured internet, bus foreground location and debug-only HTTP. Review signing and keychain entitlements before release.',
);
