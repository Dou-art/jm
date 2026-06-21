# API Map

Source project: `jm-mobile-main`

## Shared Request Behavior

Every request uses the selected API base URL from local settings.

Default API hosts:

```text
https://www.cdnhth.club
https://www.cdnmhwscc.vip
https://www.jmapiproxyxxx.vip
https://www.cdnxxx-proxy.xyz
https://www.jmeadpoolcdn.life
```

Every request adds:

```text
tokenparam: <apiTs>,1.8.2
token: md5(<apiTs>185Hcomic3PAPP7R)
```

`apiTs` is generated once when the original Android API constants are loaded.
This port keeps the same behavior by generating it once per `JmHttpClient`.

Successful JSON responses are shaped as:

```json
{
  "code": 200,
  "data": "<base64 AES encrypted JSON string>"
}
```

The encrypted data is decrypted with AES ECB PKCS5/PKCS7 padding using the
startup token hash as the key.

## Comic API

| Android method | HTTP | Path | ArkTS method |
| --- | --- | --- | --- |
| `getComicDetail` | GET | `album?id=` | `comic.getComicDetail(id)` |
| `likeComic` | POST multipart | `like` | `comic.likeComic(id)` |
| `collectComic` | POST multipart | `favorite` | `comic.collectComic(id)` |
| `unCollectComic` | POST multipart | `favorite` | `comic.unCollectComic(id)` |
| `getHomeSwiperComicList` | GET | `promote` | `comic.getHomeSwiperComicList()` |
| `getComicPicList` | GET string | `chapter_view_template` | `comic.getComicPicList(id, shunt)` |
| `getComicList` | GET | `search` | `comic.getComicList(page, order, searchContent)` |
| `getWeekData` | GET | `week` | `comic.getWeekData()` |
| `getWeekRecommendComicList` | GET | `week/filter` | `comic.getWeekRecommendComicList(page, categoryId, typeId)` |
| `getCommentList` | GET | `forum` | `comic.getCommentList(page, comicId)` |
| `comment` | POST multipart | `comment` | `comic.comment(content, comicId, commentId)` |

## User API

| Android method | HTTP | Path | ArkTS method |
| --- | --- | --- | --- |
| `login` | POST multipart | `login` | `user.login(username, password)` |
| `getCollectComicList` | GET | `favorite` | `user.getCollectComicList(page, order, folderId)` |
| `getHistoryComicList` | GET | `watch_list` | `user.getHistoryComicList(page)` |
| `getHistoryCommentList` | GET | `forum` | `user.getHistoryCommentList(page, userId)` |
| `getSignData` | GET | `daily` | `user.getSignInData(userId)` |
| `signIn` | POST multipart | `daily_chk` | `user.signIn(userId, dailyId)` |

## Remote Setting API

| Android method | HTTP | Path | ArkTS method |
| --- | --- | --- | --- |
| `getRemoteSetting` | GET | `setting` | `remoteSetting.getRemoteSetting()` |

