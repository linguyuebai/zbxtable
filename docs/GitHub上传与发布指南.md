# GitHub 涓婁紶銆佹墦鍖呬笌涓€閿畨瑁?

鏈枃璇存槑濡備綍妫€鏌ュ伐浣滃尯銆佺敓鎴愭簮鐮佸帇缂╁寘銆佸垱寤?GitHub Release锛屽苟鍦?Linux 鎴?Windows 涓婁笅杞?Release 鑷姩瀹夎銆傚懡浠ら粯璁ゅ湪浠撳簱鏍圭洰褰曟墽琛屻€?

## 鍙戝竷鍓嶆鏌?

鍏堟鏌ュ緟鎻愪氦鏂囦欢锛岀‘璁?`config/app.conf`銆佹暟鎹簱瀵嗙爜銆佹棩蹇椼€佽繍琛屾暟鎹強鏈湴鏋勫缓鐩綍娌℃湁杩涘叆鐗堟湰搴擄細

```powershell
git status --short
git check-ignore -v config/app.conf log build dist
git diff --check
```

`config/app.conf.example` 鏄彲鎻愪氦鐨勬ā鏉匡紱瀹為檯閰嶇疆 `config/app.conf` 涓嶅簲鎻愪氦銆傛鏌ュ畬鍐嶆坊鍔犲拰鎻愪氦浠ｇ爜锛?

```bash
git switch 3.0
git pull --rebase origin 3.0
git add -A
git status --short
git diff --cached --check
git commit -m "feat: 瀹屽杽宸℃鍜屽彂甯冨畨瑁呮祦绋?
git push origin 3.0
```

棣栨鎺ㄩ€佸墠搴旂‘璁?`origin` 鎸囧悜鑷繁鐨勪粨搴撴垨宸茶幏鎺堟潈鐨勪笂娓镐粨搴撱€傛姝ラ鍙帹閫佷唬鐮佸垎鏀紱鍒涘缓 Release 鏄悗缁崟鐙搷浣溿€?

## 涓€閿鏌ュ苟鐢熸垚鍙戝竷鍖?

鑴氭湰鑷姩妫€鏌ュ繀闇€鏂囦欢銆佹晱鎰?鏋勫缓鐩綍鍜?`git diff --check`锛岄殢鍚庡湪 `dist/` 鐢熸垚 `zbxtable-v3.0.8/` 鍙戝竷鐩綍銆乑IP銆丩inux 鍙敤鐨?TAR.GZ 鍙婂悇鑷?SHA256 鏂囦欢锛屽苟鏀堕泦 Windows/Linux 涓€閿畨瑁呭拰鍗歌浇鑴氭湰銆俙dist/` 鍜屽彂甯冧复鏃剁洰褰曞凡鍔犲叆蹇界暐瑙勫垯銆?

### 搴旇涓婁紶鍝釜鍘嬬缉鍖咃紵

鏈」鐩綋鍓嶄娇鐢ㄢ€滄簮鐮佸畬鏁村彂甯冨寘鈥濇柟寮忥細

| 鏂囦欢 | 鐢ㄩ€?|
|---|---|
| `zbxtable-v3.0.8-source.tar.gz` | Linux銆乁buntu銆丏ebian銆丆entOS 鎺ㄨ崘浣跨敤锛涗繚鐣?Linux 鑴氭湰鏉冮檺锛屽寘鍚唬鐮併€佹枃妗ｃ€侀厤缃ā鏉裤€佸畨瑁?杩愯鑴氭湰浠ュ強宸插瓨鍦ㄧ殑鍓嶇鏂囦欢锛屾槸鏈嶅姟鍣ㄧ浼樺厛閫夋嫨鐨勫畬鏁村寘銆?|
| `zbxtable-v3.0.8-source.zip` | Windows Server 鎺ㄨ崘浣跨敤锛涘寘鍚唬鐮併€佹枃妗ｃ€侀厤缃ā鏉垮拰瀹夎/杩愯鑴氭湰銆俉indows 鐢熸垚鐨?ZIP 鍙兘涓嶅惈鍓嶇鏋勫缓浜х墿锛屽畨瑁呰剼鏈細鑷姩鏋勫缓鍓嶇銆?|
| 鍚屽悕 `.sha256` | 涓嬭浇鍚庢牎楠屾枃浠跺畬鏁存€э紝蹇呴』鍜屽搴斿帇缂╁寘閰嶅浣跨敤銆?|

`dist/zbxtable-v3.0.8/` 鏄В鍘嬪悗鐨勫畬鏁寸洰褰曪紝閫傚悎閫氳繃 `scp` 鎴栧唴缃戞枃浠朵紶杈撶洿鎺ヤ笂浼犲埌 Linux锛涗笂浼犵洰褰曞悗鍙互鐩存帴杩愯 `scripts/install.sh`銆傛寮忎笂浼?GitHub 鏃朵笂浼犲帇缂╁寘銆佹牎楠屾枃浠跺拰鍏ュ彛鑴氭湰鍗冲彲锛屼笉闇€瑕佷笂浼?`dist/` 鏁翠釜鐩綍銆?

鍥犳锛孡inux 鏈嶅姟鍣ㄤ笂浼?`source.tar.gz` 鍜屽搴?`.tar.gz.sha256`锛沇indows 鏈嶅姟鍣ㄤ笂浼?`source.zip` 鍜屽搴?`.zip.sha256`銆備笉瑕佷笂浼犳棫鐗堟湰鍚嶇О涓甫 `dirty` 鐨勫紑鍙戝寘銆傜増鏈彿搴旀浛鎹㈡垚浣犲疄闄呭彂甯冪殑鐗堟湰锛屼緥濡?`v3.0.8`銆?

鍘嬬缉鍖呬腑涓嶆斁鐪熷疄鏁版嵁搴撳瘑鐮併€佹棩蹇椼€佽繍琛屾暟鎹拰鏈湴 `build/` 鐩綍銆侺inux TAR.GZ 鍦?Git Bash/Linux 鐜鎵撳寘鏃朵細鍖呭惈宸叉湁鐨?`api/v1/web/web/`锛涘鏋滃寘鍐呮病鏈夊墠绔枃浠讹紝瀹夎鑴氭湰浼氳嚜鍔ㄥ皾璇曚笅杞?`zbxtable-web` 骞舵瀯寤恒€?

Windows PowerShell锛?

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\publish-release.ps1 -Version v3.0.8
```

Linux/macOS锛?

```bash
bash scripts/publish-release.sh
```

鑴氭湰榛樿鍙鏌ュ拰鎵撳寘锛屼笉浼氫笂浼犮€傛寚瀹氱増鏈彲浣跨敤 `ZBXTABLE_VERSION` 鐜鍙橀噺锛沇indows 涔熷彲浼?`-Version`銆傛湭鎸囧畾鏃朵娇鐢?`git describe` 鐢熸垚鐗堟湰鍚嶃€侺inux 绔獙璇佹牎楠屽拰锛?

```bash
sha256sum -c dist/*.tar.gz.sha256
```

Windows 绔彲楠岃瘉锛?

```powershell
Get-FileHash .\dist\*.zip -Algorithm SHA256
```

鎵撳寘瀹屾垚鍚庯紝鍙互鍏堟鏌ュ帇缂╁寘涓槸鍚﹀瓨鍦ㄥ叧閿枃浠讹細

```bash
tar -tzf dist/zbxtable-v3.0.8-source.tar.gz | grep -E '(^|/)(README.zh-CN.md|config/app.conf.example|scripts/install.sh|scripts/run.sh)$'
```

Windows PowerShell锛?

```powershell
tar.exe -tf .\dist\zbxtable-v3.0.8-source.zip | Select-String 'README.zh-CN.md|config/app.conf.example|scripts/install.ps1|scripts/run.ps1'
```

鍙戝竷鍖呭寘鎷唬鐮併€佹枃妗ｃ€佸畨瑁呰剼鏈拰绀轰緥閰嶇疆锛屼笉鍖呮嫭鐪熷疄 `config/app.conf`銆佹棩蹇椼€佽繍琛屾暟鎹拰 `build/`銆乣dist/`銆侺inux 绔嫢宸叉湁鏋勫缓濂界殑 `api/v1/web/web/`锛屼細鎶婂墠绔竴骞舵墦鍏ュ寘锛涙病鏈夋椂瀹夎姝ラ浼氬皾璇曚笅杞藉苟鏋勫缓鍓嶇銆?

## 鍒涘缓 GitHub Release 骞朵笂浼犺祫浜?

鍏堟帹閫佺浉搴斾唬鐮佸垎鏀苟纭鐗堟湰鍙凤紝鐒跺悗鐧诲綍 GitHub CLI锛?

```bash
gh auth login
```

Windows锛?

```powershell
.\scripts\publish-release.ps1 -Version v3.0.8 -Upload
```

鍙戝竷鍒拌嚜宸辩殑浠撳簱鏃讹細

```powershell
.\scripts\publish-release.ps1 `
  -Version v3.0.8 `
  -Repository your-name/zbxtable `
  -Upload
```

Linux/macOS锛?

```bash
ZBXTABLE_VERSION=v3.0.8 bash scripts/publish-release.sh --upload
```

Linux 鍙戝竷鍒拌嚜宸辩殑浠撳簱锛?

```bash
ZBXTABLE_VERSION=v3.0.8 \
  bash scripts/publish-release.sh \
  --repository=your-name/zbxtable \
  --upload
```

涓婁紶浼氬垱寤?`v3.0.8` Release锛屽苟闄勪笂 ZIP/TAR.GZ銆佹牎楠屽拰鍜屽畨瑁呰剼鏈€傞渶瑕佸厛瀹￠槄 Release 鍐嶅叕寮€鏃讹紝鍔?`-Draft`锛圥owerShell锛夋垨 `--draft`锛圫hell锛夈€傝剼鏈鏌ラ粯璁ゅ紑鍚紱鍙湁鍦ㄦ湁鎰忚烦杩囨椂鎵嶄紶 `-SkipChecks` 鎴?`--skip-checks`銆?

涔熷彲浠ュ湪 GitHub 缃戦〉涓墜宸ヤ笂浼狅細杩涘叆浠撳簱 **Releases 鈫?Draft a new release**锛屽～鍐?Tag锛堜緥濡?`v3.0.8`锛夛紝鎶婁互涓嬫枃浠舵嫋鍒?Assets锛?

```text
zbxtable-v3.0.8-source.tar.gz
zbxtable-v3.0.8-source.tar.gz.sha256
zbxtable-v3.0.8-source.zip
zbxtable-v3.0.8-source.zip.sha256
scripts/install-release.sh
scripts/install-release.ps1
scripts/install-release.bat
scripts/install.sh
scripts/install.ps1
scripts/install.bat
scripts/bootstrap-linux.sh
scripts/uninstall.sh
scripts/uninstall.ps1
scripts/uninstall.bat
```

缃戦〉涓婁紶鍚庣偣鍑?**Publish release**銆傚彧鏈?Release 宸插彂甯冨苟鍖呭惈杩欎簺璧勪骇鏃讹紝`releases/latest/download/...` 涓嬭浇鍦板潃鎵嶄細鐢熸晥銆?

## 浠?GitHub Release 鑷姩瀹夎

鑷姩瀹夎鍣ㄤ粠 GitHub Releases API 涓嬭浇鏈€鏂?Release 鎴栨寚瀹氱増鏈紝楠岃瘉 SHA256锛岃В鍘嬪苟璋冪敤浠撳簱瀹夎鑴氭湰銆傚畠涓嶄細鍋滄鎴栦慨鏀?Zabbix 鏈嶅姟銆傞娆￠儴缃蹭細鎻愮ず鏁版嵁搴撹繛鎺ヤ俊鎭紝閰嶇疆榛樿杩炴帴鐜版湁 Zabbix 鏁版嵁搴擄紱璇蜂娇鐢ㄦ湁寤鸿〃鏉冮檺鐨勭嫭绔嬫暟鎹簱璐﹀彿锛屽苟纭搴旂敤绔彛绌洪棽銆傚畬鏁?TAR.GZ 宸插寘鍚墠绔椂锛屾湇鍔″櫒鍙渶瑕?Go 1.24+锛涘鏋滃帇缂╁寘娌℃湁鍓嶇锛屽畨瑁呰剼鏈墠闇€瑕?Git銆丯ode.js/npm锛堣嫢鏈?yarn.lock 涓斿畨瑁呬簡 Yarn锛屼篃鍙敤 Yarn锛変互鍙婄綉缁滆闂?GitHub/npm銆傝烦杩囧墠绔瀯寤哄彲浼?`--skip-frontend` / `-SkipFrontend`锛屾鏃朵互 API 妯″紡杩愯銆?

### 鏂瑰紡涓€锛氭湇鍔″櫒鐩存帴浠?Release 瀹夎锛堟帹鑽愶級

3.0.8 涓€琛屽畨瑁呭懡浠わ紙鑷姩鐜妫€娴嬨€佷緷璧栧畨瑁呫€丼HA256 鏍￠獙銆佹枃浠舵鏌ャ€佺紪璇戙€佸惎鍔ㄥ拰鐘舵€佽緭鍑猴級锛?

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash -s -- --version=v3.0.8 --install-deps --install-root=/opt/zbxtable
```

涓嶅惎鍔ㄦ湇鍔★紝浠呭畬鎴愬畨瑁咃細

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash -s -- --version=v3.0.8 --install-deps --install-root=/opt/zbxtable --no-start
```

鑴氭湰浼氳緭鍑哄垎闃舵杩涘害銆佺幆澧冩鏌ャ€丷elease 鍦板潃銆佸帇缂╁寘鍚嶇О銆丼HA256 缁撴灉銆佸繀闇€鏂囦欢妫€鏌ャ€佸畨瑁呰矾寰勩€佺紪璇戠粨鏋溿€乻ystemd 鐘舵€併€佽闂湴鍧€銆侀粯璁よ处鍙峰瘑鐮佸拰闃茬伀澧欏鐞嗙粨鏋溿€傛暟鎹簱瀵嗙爜涓嶄細鍐欏叆 Release锛涢娆″畨瑁呮椂鐢?`scripts/install.sh` 浜や簰璇诲彇銆傞粯璁よ处鍙蜂负 `admin`锛屽垵濮嬪瘑鐮佷负 `Zbxtable`锛岄娆＄櫥褰曞悗蹇呴』淇敼銆?

Docker 涓€琛屽畨瑁咃紙鑷姩妫€鏌?Docker锛涚己灏?Docker 鏃跺畨瑁咃紝鏀寔绔彛鍙傛暟锛夛細

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh | sudo bash -s -- --version=v3.0.8 --docker-install --port=8089
```

### 涓€閿洿鏂版垨淇鐜版湁瀹夎

`--update` 鏄繚鐣欓厤缃殑闈炰氦浜掑崌绾у叆鍙ｏ紝浼氳嚜鍔ㄥ垽鏂綋鍓嶈繍琛岀殑鏄?systemd 杩樻槸 Docker锛屼笅杞芥渶鏂?Release锛屾浛鎹㈢▼搴忓拰鍓嶇骞舵墽琛屽仴搴锋鏌ャ€傞渶瑕佹寚瀹氬浐瀹氱増鏈垨鍙慨澶嶅綋鍓嶇増鏈椂鍙娇鐢?`--repair --version=...`銆?

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh \
  | sudo bash -s -- --update --install-root=/opt/zbxtable

# 淇濈暀閰嶇疆锛岄噸鏂伴儴缃?v3.0.8锛堣嚜鍔ㄨ瘑鍒?systemd/Docker锛?
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/install-release.sh \
  | sudo bash -s -- --repair --version=v3.0.8 --install-root=/opt/zbxtable
```

宸叉湁 Docker 鏃朵娇鐢?`--docker`锛涜嚜瀹氫箟绔彛鍙敼涓?`--port=9088`銆侱ocker 瀹夎浼氭瀯寤哄甫鍓嶇鐨勯暅鍍忋€佹寕杞?`config/` 鍜岃繍琛岀洰褰曘€佸惎鍔?`zbxtable` 瀹瑰櫒锛屽苟鐢?HTTP 璇锋眰楠岃瘉椤甸潰銆傛暟鎹簱杩炴帴浠嶇敱 `config/app.conf` 鎺у埗銆?

Ubuntu銆丏ebian銆丆entOS 绛?Linux锛氶渶瑕?`curl`銆乣tar`銆乣sha256sum`銆乣python3`銆丟o 1.24+銆丟it 鍜?Node.js/npm銆備笅杞借剼鏈悗鎵ц锛?

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh -o install-release.sh
chmod +x install-release.sh
sudo bash install-release.sh --install-root=/opt/zbxtable
```

棣栨閮ㄧ讲涓斿笇鏈涜剼鏈嚜鍔ㄥ畨瑁呭熀纭€鐜锛坈url銆乼ar銆丳ython銆丟it銆丯ode.js/npm锛屼互鍙?Go 1.24.0锛夋椂锛?

```bash
sudo bash install-release.sh --install-deps --install-root=/opt/zbxtable
```

`--install-deps` 鍙敮鎸?apt銆乨nf銆亂um銆亃ypper銆乤pk锛屼細瀹夎鏈€灏忓熀纭€渚濊禆锛涘畬鏁村寘宸插唴缃墠绔椂涓嶄細瀹夎 Node.js銆傚凡鏈?Go 1.24+ 鏃朵笉浼氳鐩栥€傛病鏈夎鍙傛暟鏃惰剼鏈彧妫€娴嬬幆澧冨苟鍦ㄧ己灏戜緷璧栨椂鍋滄銆傞噸鏂版墽琛屽畨瑁呭櫒榛樿瑕嗙洊鏃х殑 ZbxTable 绋嬪簭銆佷繚鐣?`config/app.conf`锛屽苟鍏堝仠姝㈡棫鐨?`zbxtable.service`锛涗娇鐢?`--no-overwrite` 鍙姝㈣鐩栥€?

瀹夎鎸囧畾鐗堟湰锛?

```bash
sudo bash install-release.sh --version=v3.0.8 --install-root=/opt/zbxtable
```

Windows Server锛氶渶瑕?PowerShell 5.1+銆丟o 1.24+銆丟it銆丯ode.js/npm銆備互绠＄悊鍛?PowerShell 鎵ц锛?

```powershell
iwr https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.ps1 -OutFile install-release.ps1
powershell.exe -ExecutionPolicy Bypass -File .\install-release.ps1 -InstallRoot C:\ProgramData\zbxtable
```

### 鏂瑰紡浜岋細鍏堜笂浼犲畬鏁村帇缂╁寘锛屽啀杩愯鍖呭唴鑴氭湰

Linux锛?

```bash
scp dist/zbxtable-v3.0.8-source.tar.gz dist/zbxtable-v3.0.8-source.tar.gz.sha256 user@server:/tmp/
ssh user@server
sudo mkdir -p /opt/zbxtable-src
sudo tar -xzf /tmp/zbxtable-v3.0.8-source.tar.gz -C /opt/zbxtable-src --strip-components=1
cd /opt/zbxtable-src
sudo sha256sum -c /tmp/zbxtable-v3.0.8-source.tar.gz.sha256
sudo env ZBXTABLE_DB_NAME=zbxtable ZBXTABLE_DB_USER=zbxtable ZBXTABLE_DB_PASS='鏁版嵁搴撳瘑鐮? bash scripts/install.sh
sudo bash scripts/run.sh
```

濡傛灉浣跨敤 systemd 骞朵互 root 鎵ц瀹夎锛屽畨瑁呰剼鏈細鍒涘缓 `zbxtable` 鏈嶅姟锛涘畨瑁呭悗鎵ц `sudo systemctl start zbxtable`锛屾煡鐪嬬姸鎬佺敤 `sudo systemctl status zbxtable`銆?

涔熷彲浠ョ洿鎺ヤ笂浼犲凡鐢熸垚鐨勭洰褰曪細

```bash
scp -r dist/zbxtable-v3.0.8 user@server:/tmp/
ssh user@server
sudo rm -rf /opt/zbxtable
sudo mv /tmp/zbxtable-v3.0.8 /opt/zbxtable
cd /opt/zbxtable
sudo env ZBXTABLE_DB_NAME=zbxtable ZBXTABLE_DB_USER=zbxtable \
  ZBXTABLE_DB_PASS='鏁版嵁搴撳瘑鐮? bash scripts/install.sh
sudo systemctl start zbxtable
```

濡傛灉鏄洿鎺ヤ笂浼犵洰褰曚笖鏈嶅姟鍣ㄨ繕娌℃湁瀹夎渚濊禆锛屽彲鍏堟墽琛岋細

```bash
sudo bash scripts/bootstrap-linux.sh
sudo env ZBXTABLE_DB_NAME=zbxtable ZBXTABLE_DB_USER=zbxtable \
  ZBXTABLE_DB_PASS='鏁版嵁搴撳瘑鐮? bash scripts/install.sh
```

Windows PowerShell锛?

```powershell
Expand-Archive .\zbxtable-v3.0.8-source.zip -DestinationPath C:\Temp\zbxtable
cd C:\Temp\zbxtable\zbxtable-v3.0.8
Copy-Item config\app.conf.example config\app.conf
notepad config\app.conf
powershell.exe -ExecutionPolicy Bypass -File .\scripts\install.ps1
powershell.exe -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

鎶?`config/app.conf` 涓殑鏁版嵁搴撳湴鍧€銆佽处鍙枫€佸瘑鐮併€佸簱鍚嶅拰 `httpport` 濉ソ鍚庡啀杩愯瀹夎銆傚凡鏈夐厤缃崌绾ф椂涓嶈鐢ㄧず渚嬫枃浠惰鐩栫湡瀹為厤缃€?

瀹夎鎸囧畾鐗堟湰锛?

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install-release.ps1 -Version v3.0.8 -InstallRoot C:\ProgramData\zbxtable
```

Linux Release 瀹夎鍣ㄩ粯璁よ鐩栨棫鐨?ZbxTable 绋嬪簭锛屾浛鎹㈠墠浼氬仠姝㈠苟閲嶆柊鍚姩 `zbxtable.service`锛岀幇鏈?`config/app.conf` 浼氫繚鐣欙紱浣跨敤 `--no-overwrite` 鍙敼涓哄彂鐜扮洰褰曞瓨鍦ㄥ氨鍋滄銆傚姟蹇呭厛澶囦唤閰嶇疆鍜屾暟鎹簱銆傚畨瑁呭櫒涓嶄細鍋滄鎴栦慨鏀?Zabbix 鏈嶅姟銆俉indows 瀹夎瀹屾垚鍚庤繍琛?`scripts\run.ps1`銆?

### 涓€閿嵏杞?

涓€琛屽交搴曞嵏杞斤細

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/download/v3.0.8/uninstall.sh | sudo bash -s -- --install-root=/opt/zbxtable --runtime-root=/usr/local/zbxtable --purge --yes
```

鍗歌浇鑴氭湰鍙鐞嗗悕涓?`zbxtable` 鐨勬湇鍔″拰 ZbxTable 鑷韩鐩綍锛屼笉浼氬仠姝?Zabbix Server銆乑abbix Agent銆乑abbix Proxy锛屼篃涓嶄細鍒犻櫎鍏辩敤鏁版嵁搴撲腑鐨?Zabbix 鍘熺敓琛ㄣ€?

Linux 榛樿鍒犻櫎绋嬪簭鍜岃繍琛屾枃浠讹紝浣嗕繚鐣?`config/app.conf`锛?

```bash
cd /opt/zbxtable
sudo bash scripts/uninstall.sh --install-root=/opt/zbxtable --yes
```

濡傛灉瀹夎鐩綍宸茶璇垹锛屼篃鍙互鐩存帴浠?Release 涓嬭浇鍗歌浇鑴氭湰锛?

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/uninstall.sh -o uninstall.sh
chmod +x uninstall.sh
sudo bash uninstall.sh --install-root=/opt/zbxtable --runtime-root=/usr/local/zbxtable --purge --yes
```

褰诲簳鍒犻櫎绋嬪簭銆侀厤缃拰鐩綍锛?

```bash
sudo bash scripts/uninstall.sh \
  --install-root=/opt/zbxtable \
  --runtime-root=/usr/local/zbxtable \
  --purge --yes
```

涓嶅甫 `--yes` 鏃朵細瑕佹眰杈撳叆 `DELETE` 纭銆俙--purge` 鍙垹闄?ZbxTable 鏂囦欢锛屼笉鍒犻櫎 Zabbix 鏁版嵁搴撱€乑abbix 鏈嶅姟鎴栨暟鎹簱涓殑 Zabbix 琛ㄣ€傚畨瑁呰剼鏈垱寤虹殑 `zbxtable` 绯荤粺鐢ㄦ埛榛樿淇濈暀锛岀‘璁ゆ棤鍏朵粬鐢ㄩ€斿悗鍐嶆墜宸ュ垹闄ゃ€?

Windows PowerShell锛?

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -InstallRoot C:\ProgramData\zbxtable
```

涔熷彲浠ョ洿鎺ヤ笅杞藉嵏杞借剼鏈細

```powershell
iwr https://github.com/linguyuebai/zbxtable/releases/latest/download/uninstall.ps1 -OutFile uninstall.ps1
powershell.exe -ExecutionPolicy Bypass -File .\uninstall.ps1 -InstallRoot C:\ProgramData\zbxtable
```

褰诲簳鍒犻櫎锛?

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 `
  -InstallRoot C:\ProgramData\zbxtable -Purge -Yes
```

## 瀹夎鍚庢鏌?

1. 纭 `config/app.conf` 涓暟鎹簱鍦板潃銆佸簱鍚嶃€佽处鍙峰拰绔彛姝ｇ‘锛屼笖 Web 绔彛娌℃湁涓?Zabbix 鍐茬獊銆?
2. 纭 ZbxTable 鏁版嵁搴撹处鍙峰彧鎷ユ湁杩愯鎵€闇€鏉冮檺锛涘叡鐢ㄦ暟鎹簱鏃讹紝ZbxTable 鑷湁琛ㄤ娇鐢?`zbxtable_` 鍓嶇紑銆?
3. 鍚姩鏈嶅姟骞舵鏌ユ棩蹇椾笌 Web 椤甸潰锛涘厛鎵嬪姩鎵ц涓€娆″贰妫€锛岀‘璁?Zabbix API銆佹棩蹇楃洃鎺ч」鍜岄€氱煡濯掍粙宸ヤ綔姝ｅ父銆?
4. 鐢熶骇鐜鍏堝浠芥暟鎹簱鍙婇厤缃紝鍐嶅惎鐢ㄥ畾鏃朵换鍔°€?

### 甯哥敤杩愯鍛戒护

```bash
# Linux
sudo systemctl status zbxtable
sudo journalctl -u zbxtable -f

# 闈?systemd 鐜
bash scripts/run.sh
```

```powershell
# Windows
powershell.exe -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

娴忚鍣ㄨ闂?`http://鏈嶅姟鍣↖P:8089`锛堝鏋滀慨鏀逛簡 `httpport`锛屼娇鐢ㄤ慨鏀瑰悗鐨勭鍙ｏ級銆傞粯璁よ处鍙峰瘑鐮佽浠ラ」鐩綋鍓嶅垵濮嬪寲閫昏緫涓哄噯锛岄娆＄櫥褰曞悗绔嬪嵆淇敼瀵嗙爜銆?

Windows 鏃ュ織閲囬泦銆佸紓甯哥櫥褰曠洃鎺с€乑abbix 涓枃鐣岄潰閰嶇疆銆佽Е鍙戝櫒鍜岄偖浠堕€氱煡姝ラ锛屽弬瑙乕Zabbix 宸℃涓?Windows 鏃ュ織瀵规帴鎸囧崡](./Zabbix-宸℃涓嶹indows鏃ュ織瀵规帴鎸囧崡.md)銆?`n