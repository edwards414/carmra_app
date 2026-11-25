# BOM 掃描（carmra_app）

用手機相機掃 LCSC 零件袋上的 QR code，判斷零件是不是在這塊 PCB 的 BOM 裡，是的話自動打勾。

```
電腦（macOS App）                          手機（iOS App）
┌──────────────────────────┐   同一個 Wi-Fi  ┌───────────────────────┐
│ 上傳 ibom.html → 建立專案   │◄──── HTTP ────►│ 選專案 → 掃 LCSC 標籤    │
│ 專案存在本機 + LAN 伺服器    │   PIN 驗證      │ 在 BOM 內 → 自動打勾     │
│ 即時看到手機打勾的進度        │                │ 不在 BOM → 紅色警告      │
└──────────────────────────┘                └───────────────────────┘
```

## 使用方式

1. **電腦**：`flutter run -d macos`（或執行 `build/macos/Build/Products/Release/BOM Scanner.app`）。
   按「上傳 ibom.html 建立專案」，選 KiCad InteractiveHtmlBom 產生的 `ibom.html`。
   產生 ibom 時欄位要包含 LCSC 編號，例如 `--extra-fields LCSC,MPN`。
2. **手機**：打開 App，掃電腦左下「手機連線」畫面上的 QR code（含 IP、port、PIN）。
   之後會記住這台電腦，開 App 就自動連線。
3. 選專案 → 對著零件袋標籤的 QR code：
   - 🟢 **在 BOM 內，已打勾**：顯示位號（R102, R204…）、需要數量、本包數量
   - 🔵 **之前已打勾**：同一包重複掃不會重複累計數量；不同包會累加「已掃」
   - 🟠 **LCSC 編號不同，但型號相符**：替代料，可按按鈕手動打勾
   - 🔴 **不在這個 BOM**
4. 點清單上的項目可手動打勾 / 取消；右上 🧹 **清除全部打勾**（BOM 保留）。
   鍵盤圖示可手動輸入 LCSC 編號（標籤破損時）。

BOM 依 LCSC 編號合併：同一顆料（例如 C2986030 用在 D104、D204、D205、D206）掃一次就全部打勾。
沒有 LCSC 編號的項目顯示「無 LCSC」，只能手動打勾。

## LCSC 標籤格式

標籤 QR code 內容：

```
{pbn:PICK2205300004,on:WM2611110386001,pc:C2841530,pm:CH342F,qty:2,mc:TLAN62,cc:1,pdi:248284107,hp:0,wc:zh}
```

`pc` = LCSC 編號、`pm` = 型號（MPN）、`qty` = 數量、`on`/`pbn` = 訂單 / 揀貨單號（用來判斷是不是同一包）。

## 架構

| 路徑 | 內容 |
|---|---|
| `lib/core/` | 純 Dart：ibom.html 解析（含 LZString 解壓）、LCSC 標籤解析、比對、資料模型 |
| `lib/host/` | 電腦端：專案儲存（每個專案一個 JSON）、LAN HTTP API、桌面 UI |
| `lib/client/` | 手機端：API client、連線 / 專案清單 / 掃描頁 |
| `lib/ui/` | 共用元件（BOM 清單、掃描結果卡片） |

電腦 API（每個請求帶 `x-pin` header）：`GET /api/ping`、`GET /api/projects`、`GET /api/projects/{id}`、
`POST /api/projects/{id}/scan`、`POST /api/projects/{id}/check`、`POST /api/projects/{id}/clear`。

專案存在 `~/Library/Containers/com.edwards.bomscanner/Data/Library/Application Support/com.edwards.bomscanner/`。
PIN 第一次啟動時產生，存在同目錄的 `host.json`。

## 開發

```bash
flutter pub get
flutter analyze
flutter test
# 用真的 ibom.html 測解析
IBOM_PATH=../automation_robot/hardware/AGR-TR-S3-RLY/bom/ibom.html flutter test test/core_test.dart
```

macOS 第一次啟動時防火牆可能會問「允許接受連線」，要按允許，手機才連得到。

## 發佈到 TestFlight

```
git tag v1.0.1 && git push origin v1.0.1
        │
        ▼  .github/workflows/ios-testflight.yml（macos-26 runner）
flutter analyze / test ──► xcodebuild archive（不簽章）──► export .ipa（API key 自動簽章）──► altool 上傳 TestFlight
```

- 版本號：tag `v1.0.1` → `1.0.1`；build number = workflow run number。
- 也可以在 GitHub Actions → iOS TestFlight → Run workflow 手動觸發。
- 每次 push 到 main 會跑 `CI`（format / analyze / test）。

### 一次性設定

1. App Store Connect → Apps → ＋ 新 App：Bundle ID `com.edwards.bomscanner`（沒有的話先在
   developer.apple.com → Identifiers 註冊）。App 記錄要先存在，TestFlight 才收得到 build。
2. Repo Settings → Secrets and variables → Actions（和 mower_lawer_app 用同一把 API key）：

   | Secret | 值 |
   |---|---|
   | `APP_STORE_CONNECT_KEY_ID` | Key ID（`AuthKey_XXXXXXXXXX.p8` 檔名裡的 `XXXXXXXXXX`） |
   | `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect → Users and Access → Integrations 頁面上的 Issuer ID |
   | `APP_STORE_CONNECT_PRIVATE_KEY` | `.p8` 檔全文 |
   | `IOS_DIST_P12_BASE64` / `IOS_DIST_P12_PASSWORD` | 選用，Apple Distribution 憑證 |

   ```bash
   gh secret set APP_STORE_CONNECT_KEY_ID --body XXXXXXXXXX
   gh secret set APP_STORE_CONNECT_ISSUER_ID --body <issuer-id>
   gh secret set APP_STORE_CONNECT_PRIVATE_KEY < ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
   ```
