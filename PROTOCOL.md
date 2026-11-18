# LAN Share — โปรโตคอลสำหรับแอปอื่น (เช่นแอป Android)

เอกสารนี้อธิบายทุกอย่างที่แอปอื่นต้องรู้เพื่อทำงานร่วมกับ LAN Share บน PC
แนะนำให้แอปมือถือใช้ **HTTP/JSON API** (ข้อ 2) เพราะใช้ไลบรารีมาตรฐานได้ทันที (OkHttp, Retrofit, Ktor, `HttpURLConnection`)
ส่วน **โปรโตคอลไบนารี** (ข้อ 3) คือสิ่งที่ PC ใช้คุยกันเอง ใช้เมื่ออยากให้ PC เปิดดูไฟล์ในมือถือได้ด้วย

| สิ่งที่ใช้ | ค่า |
|---|---|
| ค้นหาเครื่อง | UDP broadcast พอร์ต **50506** |
| ไฟล์ / API | TCP พอร์ต **50505** (เปลี่ยนได้ เครื่องประกาศพอร์ตจริงใน UDP) — พอร์ตเดียวรับทั้ง HTTP และไบนารี |
| ข้อความทุกอย่าง | UTF-8, path ใช้ `/` คั่นเสมอ |

---

## 1. ค้นหาเครื่อง (UDP 50506)

ทุกเครื่องส่ง datagram นี้ทุก 3 วินาทีไปที่ `255.255.255.255:50506` และ broadcast address ของแต่ละวง

```
LSH2|<id>|<tcpPort>|<name>|<os>|<caps>|<icon>
```

| ฟิลด์ | ความหมาย |
|---|---|
| `id` | สุ่มใหม่ทุกครั้งที่เปิดโปรแกรม ใช้แยกเครื่อง และไม่สนใจแพ็กเก็ตที่ `id` เป็นของตัวเอง |
| `tcpPort` | พอร์ต TCP ของเครื่องนั้น |
| `name` | ชื่อเครื่อง (ไม่มีอักขระ `|`) |
| `os` | `windows` `linux` `macos` `android` `ios` `bsd` |
| `caps` | คั่นด้วย `,` — `bin` = เปิดให้ไล่ดูไฟล์ด้วยโปรโตคอลไบนารี, `http` = มี HTTP API, `push` = รับไฟล์ที่ส่งมาได้ |
| `icon` | ไอคอนที่ผู้ใช้เลือก `<ชนิด>.<สี>` — ชนิด: `desktop laptop phone tablet server tv store megaphone`, สี `0`–`7` (ฟ้า ม่วง เขียวน้ำทะเล เขียว ส้ม ชมพู แดง เทา) ไม่มี = เลือกตาม `os` |

`name` เป็นชื่อที่ผู้ใช้ตั้ง **ค่าเริ่มต้นคือว่าง** (ไม่ส่งชื่อคอมพิวเตอร์จริง) — ถ้าว่างให้แสดง IP แทน แอปมือถือควรทำแบบเดียวกัน

**การเชื่อมต่ออัตโนมัติ** (ทำให้เจอกันแม้ broadcast ถูกบล็อก):
- เมื่อได้ยิน `id` ใหม่ครั้งแรก ให้ส่งแพ็กเก็ตของตัวเองกลับไปที่ IP นั้นแบบ unicast ทันที
- ส่งแพ็กเก็ตแบบ unicast ไปยังเครื่องที่เคยเจอ (PC จำไว้สูงสุด 32 เครื่อง) ทุก 3 วินาที
- ทุก 60 วินาที ส่งแพ็กเก็ตไปทุก IP ใน /24 ของตัวเอง (.1–.254) เครื่องที่ได้รับจะตอบกลับตามข้อแรก

แอป Android:
- **ฟังอย่างเดียว** ก็พอสำหรับหา PC (เปิด `MulticastLock` ก่อน ไม่งั้น Android จะทิ้ง broadcast)
- ถ้าอยากให้ PC เห็นมือถือในแถบซ้าย ให้ส่ง `LSH2|<id>|<port>|<ชื่อ>|android|<caps>` ทุก 3 วินาทีด้วย
  - ถ้ามือถือยังไม่มีเซิร์ฟเวอร์ ให้ส่ง `caps` เป็น `none` แล้ว PC จะแสดงเป็นอุปกรณ์ที่ "ยังเปิดให้ดูไฟล์ไม่ได้"
  - ถ้าทำโปรโตคอลไบนารีฝั่งเซิร์ฟเวอร์ (ข้อ 3) ให้ใส่ `bin` แล้ว PC จะเปิดดูไฟล์ในมือถือได้ทันที
- PC ถือว่าเครื่องออฟไลน์เมื่อไม่ได้ยินเกิน 12 วินาที

---

## 2. HTTP / JSON API (แนะนำสำหรับมือถือ)

`http://<ip>:<tcpPort>` — HTTP/1.1, หนึ่ง request ต่อหนึ่งการเชื่อมต่อ (เซิร์ฟเวอร์ตอบ `Connection: close`)

ทุก request ควรส่ง header `X-LanShare-Name: <ชื่ออุปกรณ์ แบบ percent-encoded UTF-8>`
(หรือพารามิเตอร์ `client=`) เพื่อให้ PC แสดงชื่อในการ์ดการถ่ายโอนและหน้าต่างถามยืนยัน

ข้อผิดพลาดตอบเป็น `{"error":"ข้อความ"}` พร้อม status: `400` path ไม่ถูกต้อง (เช่นมี `..`), `403` ถูกปฏิเสธ/Host ไม่อนุญาต,
`404` ไม่พบหรือเลิกแชร์แล้ว, `405` method ผิด, `410` session ปิดแล้ว, `411` ไม่มี Content-Length, `416` Range ผิด

### `GET /api/info`
```json
{"app":"LanShare","protocol":2,"api":1,"id":"7ED745EA27B2","name":"","icon":"desktop.0","os":"windows",
 "port":50505,"caps":["bin","http","push"],"shares":2,"autoAccept":false}
```
ใช้ตรวจว่าเป็น LAN Share และเช็ค `api` (เวอร์ชันของ HTTP API — ตอนนี้ `1`)

### `GET /api/list?path=<path>`
`path` ว่าง = รายการแชร์ระดับบนสุด, `ชื่อแชร์/โฟลเดอร์ย่อย` = ข้างในแชร์
```json
{"path":"src/sub","items":[
  {"name":"deep","dir":true,"size":0,"mtime":1795008020},
  {"name":"big.bin","dir":false,"size":5000000,"mtime":1795008020}]}
```
`mtime` = Unix time (วินาที, UTC) — ไม่เรียงลำดับมาให้ (แอปเรียงเอง เช่นโฟลเดอร์ก่อน)

### `GET /api/tree?path=<path>`
ทุกไฟล์/โฟลเดอร์ใต้ `path` (ใช้ตอนดาวน์โหลดทั้งโฟลเดอร์) — สูงสุด 200,000 รายการ
```json
{"path":"src","files":3,"bytes":5000011,"items":[
  {"path":"src","rel":"src","dir":true},
  {"path":"src/a.txt","rel":"src/a.txt","dir":false,"size":6},
  {"path":"src/sub/big.bin","rel":"src/sub/big.bin","dir":false,"size":5000000}]}
```
`path` ใช้กับ `/api/file`, `rel` คือ path สำหรับบันทึกในเครื่อง

### `GET /api/file?path=<path>` (และ `HEAD`)
- ส่งเนื้อไฟล์ พร้อม `Content-Length`, `Content-Type`, `Accept-Ranges: bytes`
- **ดาวน์โหลดต่อ (resume)**: ส่ง `Range: bytes=<ตำแหน่ง>-` แล้วจะได้ `206` + `Content-Range`
- `dl=1` → `Content-Disposition: attachment` (สำหรับเบราว์เซอร์)
- ดาวน์โหลดหลายไฟล์ให้รวมเป็นการ์ดเดียวบน PC: ใส่ `batch=<id สุ่มของชุดนี้>&batchFiles=<จำนวน>&batchBytes=<ขนาดรวม>` ทุกไฟล์ในชุด

### หน้าเว็บ
- `GET /theme.css?name=<ธีม>` — สีของธีมที่ระบุ (`dark light ocean rose forest sunset coffee neon lavender mono`)
- `GET /api/themes` — รายการธีม `[{"name","label","light","bg","side","text","dim","accent","accent2"}]` สำหรับทำตัวเลือกธีม
- `GET /theme.css` — สีของธีมที่เครื่องนั้นใช้อยู่ เป็น CSS variables (`--bg --panel --card --text --dim --accent --accent2 --line --head1 --head2 ...` และ `color-scheme`)
  แอปมือถือใช้ค่าเดียวกันเพื่อให้สีตรงกับเครื่องได้
- `GET /` — หน้าเว็บสำหรับเบราว์เซอร์ (ไล่ดูโฟลเดอร์, ดาวน์โหลด, ส่งไฟล์, README.md เป็นแบนเนอร์)
- `GET /view?path=<path>` — หน้าแสดงผลไฟล์เดียว: `.md` แสดงเป็นหน้าเว็บ (รูป/GIF/PDF/MP4 ที่อ้างถึงด้วย `![](...)` ถูกฝังในหน้า),
  รูป PDF วิดีโอแสดงตรงๆ — เพิ่ม `&kiosk=1` สำหรับจอโฆษณา (ไม่มีแถบ, ตัวใหญ่, รีเฟรชเนื้อหาทุก 30 วินาที)
  แอป Android จะเปิดหน้านี้ใน WebView ก็ได้ หรือดึง `.md` ผ่าน `/api/file` แล้วแสดงเอง

### ส่งไฟล์ไปยัง PC (3 ขั้น)
1. `POST /api/push/begin?files=<จำนวน>&bytes=<ขนาดรวม>`
   PC จะถามผู้ใช้ (ถ้าไม่ได้เปิด "รับไฟล์อัตโนมัติ") — **request นี้รอจนผู้ใช้ตอบ** ตั้ง timeout ให้นานพอ (เช่น 2 นาที)
   → `200 {"token":"20267D7AA156D07D"}` หรือ `403 {"error":"rejected"}`
2. ทีละไฟล์: `PUT /api/push/file?token=<token>&path=<relPath>` body = เนื้อไฟล์ (ต้องมี `Content-Length`)
   → `200 {"ok":true}` — สร้างโฟลเดอร์ว่าง: `PUT ...&path=<rel>&dir=1` (ไม่มี body)
   ส่งพร้อมกันหลายไฟล์ได้ ไฟล์ทั้งหมดจะอยู่ในโฟลเดอร์รับไฟล์ของ PC (ชื่อซ้ำจะเป็น `ชื่อ (1)`)
3. `POST /api/push/end?token=<token>` → `200 {"ok":true,"received":2}` (ปิดการ์ดบน PC)

token หมดอายุถ้าไม่ได้ใช้ 30 นาที

### ตัวอย่างด้วย curl
```bash
curl http://192.168.1.102:50505/api/list?path=src
curl -C - -o big.bin "http://192.168.1.102:50505/api/file?path=src/sub/big.bin"
TOKEN=$(curl -s -X POST "http://192.168.1.102:50505/api/push/begin?files=1&bytes=6&client=test" | sed 's/.*"token":"\([^"]*\)".*/\1/')
curl -T a.txt "http://192.168.1.102:50505/api/push/file?token=$TOKEN&path=a.txt"
curl -X POST "http://192.168.1.102:50505/api/push/end?token=$TOKEN"
```

### ตัวอย่างโครงใน Kotlin (OkHttp) — ร่าง ยังไม่ได้ทดสอบในแอปจริง
```kotlin
val http = OkHttpClient.Builder().readTimeout(2, TimeUnit.MINUTES).build()
fun url(pc: String, ep: String, vararg q: Pair<String, String>) =
    HttpUrl.Builder().scheme("http").host(pc).port(50505).addPathSegments("api/$ep")
        .apply { q.forEach { addQueryParameter(it.first, it.second) } }.build()
val me = URLEncoder.encode("Pixel 8", "UTF-8")

// list
val json = http.newCall(Request.Builder().url(url(ip, "list", "path" to "src"))
    .header("X-LanShare-Name", me).build()).execute().body!!.string()

// upload
val begin = http.newCall(Request.Builder().url(url(ip, "push/begin", "files" to "1", "bytes" to "${f.length()}"))
    .header("X-LanShare-Name", me).post(ByteArray(0).toRequestBody()).build()).execute()
val token = JSONObject(begin.body!!.string()).getString("token")
http.newCall(Request.Builder().url(url(ip, "push/file", "token" to token, "path" to f.name))
    .header("X-LanShare-Name", me).put(f.asRequestBody()).build()).execute()
http.newCall(Request.Builder().url(url(ip, "push/end", "token" to token))
    .post(ByteArray(0).toRequestBody()).build()).execute()
```
Android 9+ ห้าม HTTP ธรรมดาโดยค่าเริ่มต้น: เพิ่ม `android:usesCleartextTraffic="true"` หรือ network security config สำหรับ IP ในวง LAN

### ความปลอดภัยของ HTTP API
- อ่านได้เฉพาะสิ่งที่แชร์ (`..`, path ว่าง, และ path ใต้ไฟล์ที่แชร์ถูกปฏิเสธ) — ไฟล์ที่ส่งมาเขียนได้เฉพาะในโฟลเดอร์รับไฟล์
- `Host` ต้องเป็น IP, ชื่อเครื่องไม่มีจุด, `localhost`, `*.local` หรือ `*.lan` — ชื่อโดเมนอินเทอร์เน็ตจะได้ `403` (กัน DNS rebinding)
- ไม่ส่ง CORS header — เว็บอื่นอ่านข้อมูลไม่ได้
- **ไม่มีรหัสผ่านและไม่เข้ารหัส** ใช้ในเครือข่ายที่ไว้ใจได้เท่านั้น (แผนอนาคต: PIN จับคู่อุปกรณ์ + HTTPS)

---

## 3. โปรโตคอลไบนารี (PC ↔ PC)

เชื่อมต่อ TCP แล้วส่ง: `"LSHR"` (4 ไบต์) + version(`byte`=2) + command(`byte`) + senderName(`str`)
จำนวนเต็มทั้งหมดเป็น **little-endian** (`ByteBuffer.order(LITTLE_ENDIAN)` ใน Java/Kotlin — `DataInputStream` เป็น big-endian ใช้ตรงๆ ไม่ได้)
`str` = ความยาว `uint16` + ไบต์ UTF-8

| command | ผู้เชื่อมต่อส่ง | ผู้รับตอบ |
|---|---|---|
| `1` PUSH ส่งไฟล์ให้ | `int32` จำนวนไฟล์, `int64` ขนาดรวม | `byte` 1=รับ / 0=ปฏิเสธ — ถ้ารับ: ผู้ส่งส่ง ENTRIES แล้วผู้รับตอบ `byte` 1 |
| `2` LIST ดูโฟลเดอร์ | `str` path | `byte` 1=ok (0 + `str` ข้อความ), `int32` n, n×(`str` ชื่อ, `byte` isDir, `int64` size, `int64` mtime) |
| `3` GET ดาวน์โหลด | `int32` n, n×`str` path | `byte` 1=ok (0 + `str`), `int32` จำนวนไฟล์, `int64` ขนาดรวม, ENTRIES — ผู้ดาวน์โหลดตอบ `byte` 1 |

ENTRIES = ซ้ำ `byte` kind: `1` = โฟลเดอร์ + `str` relPath, `2` = ไฟล์ + `str` relPath + `int64` size + ข้อมูล, `0` = จบ

ถ้าแอปมือถือทำฝั่ง **เซิร์ฟเวอร์** ของ LIST/GET/PUSH แล้วประกาศ `bin` ใน UDP PC จะเปิดดู ดาวน์โหลด และส่งไฟล์ให้มือถือได้เหมือน PC เครื่องอื่น

---

## 4. การเปลี่ยนเวอร์ชัน
- เพิ่ม endpoint หรือฟิลด์ JSON ใหม่ได้โดยไม่เพิ่ม `api` — แอปควรข้ามฟิลด์ที่ไม่รู้จัก
- เปลี่ยนแบบที่ใช้ร่วมกันไม่ได้ → เพิ่ม `api` (HTTP) หรือ version byte (ไบนารี) และ prefix UDP (`LSH2` → `LSH3`)
- เว็บในตัว (`GET /`) คือหน้า `webui.html` ใช้เป็นตัวอย่างการเรียก API ได้
