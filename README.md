# Virtual Desktop Launcher

JSONに定義したWindows仮想デスクトップを作成・再利用し、アプリの起動とウィンドウ配置をまとめて行うPowerShellスクリプトです。アプリを定義順に処理し、ウィンドウの出現を待って移動先を検証します。定義にないデスクトップは削除しません。

## 動作環境・セットアップ

- Windows 10 バージョン2004以降、またはWindows 11の対話セッション
- PowerShell 7.5以降（`pwsh.exe`）
- [PSVirtualDesktop](https://github.com/MScholtes/PSVirtualDesktop) 1.5.9以降（1.5.11以降を推奨）。デスクトップ別の壁紙はWindows 11のみ対応

```powershell
Install-Module VirtualDesktop -Scope CurrentUser
git clone https://github.com/kaseitako/virtual-desktop-launcher.git
Set-Location .\virtual-desktop-launcher
Copy-Item .\virtual-desktop-setting.sample.json .\virtual-desktop-setting.json
```

1. `virtual-desktop-setting.json` のアプリ・壁紙パスを自分の環境に合わせて編集します。
2. 設定を検証します。
3. 手動実行し、配置を確認します。

```powershell
pwsh.exe -NoProfile -File .\Startup-VirtualDesktop.ps1 -ValidateOnly
pwsh.exe -NoProfile -File .\Startup-VirtualDesktop.ps1
```

`-ValidateOnly` はJSON Schema、デスクトップ名の重複、正規表現などを検証し、環境情報をログに記録します。アプリの起動・移動や、アプリの存在・VirtualDesktopの動作確認は行いません。配置処理の実行中でも検証できます。

## 設定

[サンプル](./virtual-desktop-setting.sample.json)と[JSON Schema](./virtual-desktop-setting.schema.json)を参照してください。ルートの `desktops` 配列は必須です。空配列は有効ですが、何も配置しません。未知のプロパティや誤った型（例：`"maximized": "false"`）は検証エラーになります。

### デスクトップ

| プロパティ | 必須 | 説明 |
|---|---|---|
| `name` | はい | 一意な名前。大文字・小文字のみ異なる名前も重複扱い |
| `apps` | いいえ | アプリの配列。省略時は `[]` |
| `wallpaperAbsolutePath` | いいえ | 壁紙の絶対パス。省略・空文字列なら変更なし |
| `waitSeconds` | いいえ | 互換用の非推奨項目。警告を記録し、値は無視 |

### アプリケーション

| プロパティ | 既定値 | 説明 |
|---|---|---|
| `path` | 必須 | 実行ファイル、PATH上のコマンド、または `.lnk` |
| `arguments` | `[]` | 引数ごとの文字列配列。空白を含む引数も1要素で指定 |
| `workingDirectory` | 空 | 起動時の作業ディレクトリ。省略時は `Start-Process` の既定動作 |
| `timeoutSeconds` | `30` | ウィンドウ出現を待つ上限。1～300の整数（秒） |
| `onExisting` | `Move` | 既存ウィンドウの扱い（下表） |
| `maximized` | `false` | 配置確認後に最大化 |
| `fullscreen` | `false` | 互換用の別名。`maximized` を指定した場合はそちらを優先 |
| `windowMatch` | 自動推測 | ウィンドウの識別条件 |

| `onExisting` | 動作 |
|---|---|
| `Move` | 一致する既存ウィンドウを移動。なければ起動 |
| `Skip` | 一致する既存ウィンドウを変更しない。なければ起動・配置 |
| `Launch` | 常に起動し、新しいウィンドウを待つ。既存ウィンドウは移動しない |

同じ実行内で1つのウィンドウを複数のアプリ定義には割り当てません。`Launch` でも新しいウィンドウを作るかはアプリ次第です。単一起動型アプリが既存ウィンドウを再利用する場合はタイムアウトするため、`Move` を使ってください。

### パス・引数

- `-SettingsPath`、`-LogDirectory`、アプリの相対パス、`workingDirectory` はリポジトリ直下が基準です。設定ファイルの保存場所には依存しません。
- `path`、`workingDirectory`、`wallpaperAbsolutePath` では `%APPDATA%` などの環境変数を展開します。
- `path` が単独のコマンド名なら、リポジトリ直下の同名ファイル、PATHなどから解決します。
- `arguments` は1要素が1引数です。例：`["--profile-directory=Profile 1", "C:\\My Files\\note.txt"]`。空白を守るための追加の引用符は不要です。引数の環境変数は展開しません。

### ウィンドウの識別

`windowMatch` を省略すると、実行ファイル・リンク先のプロセス名、起動したプロセスID、ショートカット名とタイトルの一致から候補を選び、新しいウィンドウを優先します。新規に出現したことだけを理由には選びません。別プロセスを起動するランチャーやChrome/PWA/Electronアプリでは、条件を明示してください。

```json
{
  "path": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Chrome アプリ\\SoundCloud.lnk",
  "timeoutSeconds": 45,
  "maximized": true,
  "windowMatch": {
    "processName": "chrome",
    "titleRegex": "SoundCloud",
    "classNameRegex": "Chrome_WidgetWin"
  }
}
```

| 条件 | 内容 |
|---|---|
| `processName` | 拡張子を除いたプロセス名の完全一致 |
| `titleRegex` | タイトルのPowerShell正規表現 |
| `classNameRegex` | Win32ウィンドウクラス名のPowerShell正規表現 |

指定した条件をすべて満たす必要があります。大文字・小文字は区別しません。同じプロセス名を使う複数のアプリには、タイトルなども指定してください。

## ログオン時の実行

エクスプローラーのアドレスバーで `shell:startup` を開き、次のリンク先を持つショートカットを配置します。パスは設置場所に置き換えてください。

```text
"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -WindowStyle Hidden -File "C:\path\to\virtual-desktop-launcher\Startup-VirtualDesktop.ps1"
```

同じログオンセッションのExplorerプロセスを最大30秒待ちます。配置処理の二重起動は同一セッション・ユーザーのMutexで防止し、後から起動した側は終了します。

タスクスケジューラでは「ユーザーのログオン時」「ユーザーがログオンしているときのみ実行する」を指定します。非対話セッションではウィンドウを操作できません。

## ログ・終了コード

ログは既定で `logs/startup-virtual-desktop-日時-PID.jsonl` に記録します。

```powershell
pwsh.exe -NoProfile -File .\Startup-VirtualDesktop.ps1 `
    -SettingsPath .\settings\work.json -LogDirectory C:\Logs\StartupVirtualDesktop
```

環境のバージョン、デスクトップ名、アプリのパス、選択したハンドル・プロセス名、処理時間、エラーを記録します。アプリの結果は `Moved`（移動済み）、`AlreadyPlaced`（配置済み）、`Skipped`（既存を維持）、`Failed`（失敗）です。

| 終了コード | 意味 |
|---|---|
| `0` | 成功、設定検証成功、または二重起動による終了 |
| `1` | 1件以上のアプリ配置に失敗。残りのアプリは処理を継続 |
| `2` | 設定・依存関係・ログ出力先などのエラー、またはアプリのないデスクトップの作成失敗 |

壁紙の変更失敗は警告として記録し、アプリの処理を続けます。

個人設定 `virtual-desktop-setting*.json`（サンプル・スキーマを除く）、`settings/`、ログはGitの追跡対象外です。別名の個人設定は `settings/` に置いてください。ログには個人のパスなどが含まれるため、共有前に内容を確認してください。

## トラブルシューティング

| 症状 | 確認・対処 |
|---|---|
| 別のウィンドウが選ばれる | `windowMatch` にタイトル・クラス名の条件を追加 |
| 起動がタイムアウトする | パスと識別条件を確認し、必要なら `timeoutSeconds` を増やす。`Launch` ではアプリが新規ウィンドウを作るか確認 |
| ウィンドウを移動できない | 管理者で起動されたアプリとスクリプトの権限レベルをそろえる |
| Windows更新後に動かない | `Update-Module VirtualDesktop` を実行し、[対応状況](https://github.com/MScholtes/PSVirtualDesktop)とログのバージョンを確認 |

## 開発・テスト

Windows / PowerShell 7.5以降 / Pester 4.10.1を使用します。

```powershell
Save-Module Pester -RequiredVersion 4.10.1 -Path .\.tools -Repository PSGallery
pwsh.exe -NoProfile -File .\tests\Invoke-Tests.ps1
```

設定検証、ウィンドウ識別・再選択、移動の再試行、パス解決をテストします。アプリ配置はモック、既存ウィンドウは読み取りのみで確認します。引数の受け渡しには非表示のテスト用PowerShell子プロセスを使います。

実環境のコールドスタートは、`-ValidateOnly` 成功後にサインアウト・ログオンまたは再起動し、各ウィンドウの配置とログの失敗・警告を確認してください。自動テストは実際の仮想デスクトップへの移動やログオン直後の復元までは検証しません。

## 移植元・第三者コード

- [移植元のコード](https://github.com/kaseitako/random-scripts/tree/d4399f78faa017870581c7e1a09fc3a0c84182b2/powershell/startup-virtual-desktop)と[移植記録](./docs/MIGRATION.md)
- `modules/Request-NamedDesktop.psm1` はPSVirtualDesktopのサンプル由来です。[第三者の著作権・ライセンス表示](./THIRD_PARTY_NOTICES.md)を参照してください。
