# HarmonyOS Integration Notes

## Recommended DevEco Project Layout

Create a normal HarmonyOS Empty Ability project, then copy this directory:

```text
harmony-api-port/entry/src/main/ets/api
```

to:

```text
<your-harmony-project>/entry/src/main/ets/api
```

## Permission

Add network permission in `entry/src/main/module.json5`:

```json5
{
  "module": {
    "requestPermissions": [
      { "name": "ohos.permission.INTERNET" }
    ]
  }
}
```

## Basic Usage

```ts
import { createJmApiClient } from './api';

const jm = createJmApiClient({
  baseUrl: 'https://www.cdnhth.club'
});

const login = await jm.user.login('name', 'password');
if (login.ok) {
  console.info(JSON.stringify(login.data));
}
```

## Host Switching

The Android project switches hosts through `BaseUrlInterceptor`. In ArkTS:

```ts
jm.http.setBaseUrl('https://www.cdnmhwscc.vip');
```

## Cookies

The provided cookie jar is in-memory. For production, persist it through
HarmonyOS Preferences:

```ts
const cookies = jm.http.cookieJar.snapshot();
```

Restore after app start:

```ts
jm.http.cookieJar.restore(cookies);
```

## Crypto Verification

The Android code uses:

```text
AES/ECB/PKCS5Padding
key = md5(apiTs + "185Hcomic3PAPP7R")
```

HarmonyOS crypto APIs vary slightly by SDK version. Verify `Crypto.ets` in
DevEco Studio. If your SDK does not expose ECB mode directly, replace
`aesEcbPkcs5DecryptBase64` with a native C++/NAPI implementation or a vetted
pure ArkTS AES implementation.

