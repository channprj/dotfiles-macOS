# Tailscale에서만 SSH, 화면 공유, Apple 원격 관리

이 필터가 보는 포트는 SSH(22), 화면 공유(5900), Apple 원격 관리(3283)입니다. 들어올 수 있는 곳은 Tailscale 주소와 이 맥 자신(lo0)뿐입니다. 집 LAN, 다른 네트워크, 인터넷에서 이 세 포트로 오는 패킷은 막습니다.

화면 공유를 RDP라고 부르면 Microsoft 원격 데스크톱과 섞입니다. 이 필터의 화면은 5900입니다. RDP 포트 3389는 이 앵커에 없고, 막지도 않습니다.

서비스가 포트를 여는 것과 pf가 출발지를 거르는 것은 따로입니다. sshd와 화면 공유는 모든 인터페이스에서 듣습니다. 원격 관리가 꺼져 있으면 3283은 규칙만 있고 listen 하지 않습니다.

`./install.sh`는 이 설정을 건드리지 않습니다. 방화벽은 아래 스크립트를 직접 실행할 때만 바뀝니다.

## 막히는 포트

| 포트 | macOS에서 하는 일 |
| --- | --- |
| 22 | 원격 로그인, SSH |
| 5900 | 화면 공유 (VNC) |
| 3283 | Apple 원격 관리. 화면 데이터는 5900입니다. |

TCP와 UDP를 같이 봅니다. SSH와 화면 공유는 TCP로 동작하고, UDP까지 막아 두어야 그 포트의 UDP가 열려 있지 않습니다.

## 어디가 검사하나

패킷이 도착하면 세 층을 지납니다.

1. sshd와 화면 공유는 모든 네트워크 인터페이스에서 듣고 있습니다. `*.22`, `*.5900`입니다.
2. macOS 응용 프로그램 방화벽은 켜져 있고, sshd와 화면 공유의 들어오는 연결을 허용합니다.
3. 패킷 필터 pf의 앵커 `com.chann.tailscale-ssh-vnc`가 출발지를 보고, Tailscale과 loopback 외에는 버립니다.

출발지를 가르는 층은 3번입니다. Tailscale의 SSH 서버(`tailscale set --ssh`)는 꺼져 있습니다. 접속은 macOS sshd로 들어가고, pf가 그 패킷의 출발지 주소만 봅니다.

## 규칙

저장소의 [pf.anchor](pf.anchor)가 맥의 `/etc/pf.anchors/com.chann.tailscale-ssh-vnc`로 복사됩니다.

```pf
table <chann_tailscale4> const { 100.64.0.0/10 }
table <chann_tailscale6> const { fd7a:115c:a1e0::/48 }

pass in quick on lo0 proto { tcp udp } to any port { 22 5900 3283 }
pass in quick inet proto tcp from <chann_tailscale4> to any port { 22 5900 3283 } flags any keep state
pass in quick inet proto udp from <chann_tailscale4> to any port { 22 5900 3283 } keep state
pass in quick inet6 proto tcp from <chann_tailscale6> to any port { 22 5900 3283 } flags any keep state
pass in quick inet6 proto udp from <chann_tailscale6> to any port { 22 5900 3283 } keep state
block in quick proto { tcp udp } to any port { 22 5900 3283 }
```

`pfctl -sr`은 규칙 여섯 줄(통과 5, 차단 1)을 프로토콜과 포트마다 한 줄로 펼칩니다. 통과 5줄은 pass 18줄, 차단 1줄은 block 6줄입니다. `block`은 `block drop`으로 보입니다. lo0의 TCP는 파일에 `flags`가 없어서 `flags S/SA`로 보이고, 새 연결만 받습니다. Tailscale TCP의 `flags any`는 그대로 보입니다.

읽는 순서는 위에서 아래입니다.

- `100.64.0.0/10`은 Tailscale이 장비에 주는 IPv4 대역입니다. 이 맥의 주소는 `tailscale ip -4`로 볼 수 있습니다.
- `fd7a:115c:a1e0::/48`은 Tailscale IPv6 대역입니다.
- `lo0`는 이 맥 안에서 자기 자신에게 붙는 연결입니다. 로컬 클라이언트가 SSH와 화면 공유를 그대로 쓰게 두었습니다.
- 마지막 줄이 나머지 전부입니다. 집 LAN의 `192.168.x.x`, 공인 IP, 다른 IPv6가 여기 걸립니다.

`/etc/pf.conf`에는 이 앵커를 Apple 앵커보다 먼저 불러오는 줄이 있습니다. 이미 들어가 있는 이 맥의 줄은 아래입니다.

```pf
anchor "com.chann.tailscale-ssh-vnc"
load anchor "com.chann.tailscale-ssh-vnc" from "/etc/pf.anchors/com.chann.tailscale-ssh-vnc"
```

새로 설치하면 같은 줄을 `# BEGIN com.chann.tailscale-ssh-vnc`와 `# END com.chann.tailscale-ssh-vnc`로 감쌉니다. `anchor "com.apple.internet-sharing"`이 있으면 그 바로 위에 넣습니다. 그 줄이 없으면 `anchor "com.apple/*"` 바로 위에 넣습니다. 두 줄이 모두 없으면 시스템 파일을 쓰지 않고 멈춥니다.

## 차단을 맨 아래에 둔 이유

pf는 보통 마지막으로 맞은 규칙을 적용합니다. `quick`이 붙은 규칙은 맞는 즉시 결정을 끝내고, 뒤에 있는 규칙은 보지 않습니다.

통과와 차단에 모두 `quick`을 붙여 두었으므로, 이 앵커 뒤에서 평가되는 Apple 규칙이 22, 5900, 3283을 다시 열어 주지 않습니다. 통과를 먼저 두고 차단을 마지막에 두면, Tailscale에서 온 패킷은 통과에서 끝나고 LAN에서 온 패킷은 마지막 차단에서 끝납니다.

차단을 위에 두고 `quick`을 빼면, 그 차단은 "일단 기억"일 뿐입니다. 뒤에 오는 규칙이 같은 패킷을 통과로 바꿀 수 있습니다.

## 이미 붙은 Tailscale 세션을 유지하는 이유

`pfctl -f`로 규칙을 다시 읽으면 기존 연결의 state가 비어 있습니다. TCP의 기본 state 규칙은 새 연결의 SYN만 받습니다. 이미 열린 Tailscale SSH는 SYN이 아닌 패킷만 보내므로, 그 패킷이 마지막 `quick` 차단에 걸리면 세션이 끊깁니다.

Tailscale에서 오는 TCP 통과 규칙의 `flags any`는 그 패킷도 state로 받게 합니다. 그래서 이 스크립트를 이미 연결된 Tailscale SSH 안에서 실행해도 그 세션은 유지됩니다. 집 LAN이나 다른 경로로 붙어 있는 SSH 안에서 실행하면, 규칙을 읽는 순간 그 세션은 끊깁니다. 적용은 맥 앞에서 하거나 Tailscale로 붙은 셸에서 하세요.

규칙을 다시 읽은 직후 `pfctl -s info`의 `current entries`가 0인 것은 state를 비웠다는 뜻입니다. `Status: Enabled`가 필터가 켜져 있다는 줄입니다. `Enabled for N days`는 pf가 켜져 있던 시간이고, 이 앵커를 올린 시각이 아닙니다.

## 부팅 때마다 다시 켜기

pf는 규칙을 파일에 적어 두어도, 켜고 불러오는 쪽이 따로 있습니다. LaunchDaemon `com.chann.tailscale-ssh-vnc`가 부팅 때 [load.sh](load.sh)를 실행합니다.

```sh
/sbin/pfctl -E
/sbin/pfctl -nf /etc/pf.conf
/sbin/pfctl -f /etc/pf.conf
```

`-E`는 pf를 켜고 참조 횟수를 하나 올립니다. `-nf`는 적용 없이 문법만 확인합니다. `-f`는 `/etc/pf.conf`를 커널에 올립니다. `-f`는 시스템이 실행 중에 따로 넣어 둔 pf 규칙을 비울 수 있습니다. Apple이 `/etc/pf.conf` 머리에 적어 둔 주의와 같고, 이 맥은 이미 이 방법으로 규칙을 올리고 있습니다.

`load.sh`는 그 다음에 커널 규칙을 확인하고 결과를 한 단락으로 출력합니다. 저장소의 `pf.anchor`를 복사하지는 않습니다. 파일을 맥에 반영하려면 `set.sh`입니다.

`load.sh`는 먼저 경고가 나온다고 알린 다음 pfctl을 실행합니다. 성공하면 그 경고 다음에 아래 줄이 나옵니다.

```text
tailscale-pf: loaded.
Allowed: lo0 and Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48).
Ports: 22 SSH, 5900 Screen Sharing (VNC), 3283 Apple Remote Management.
Other sources to those ports are blocked.
pf expanded the anchor to 18 pass rules and 6 block rules.
The -f and ALTQ lines above are warnings, not a failed load.
Microsoft RDP (3389) is not covered.
```

경고는 실패가 아닙니다.

- `Use of -f option`은 `-nf`와 `-f`에서 한 번씩, 두 번 나옵니다.
- `No ALTQ support in kernel`은 이 macOS에 ALTQ가 없다는 줄입니다. 이 규칙은 ALTQ를 쓰지 않습니다.

`tailscale-pf: loaded.`가 없으면 앵커가 올라가지 않은 것입니다.

데몬이 켜져 있으면 재부팅 뒤에도 같은 필터가 다시 적용됩니다. 로그는 `/var/log/tailscale-pf.log`입니다.

## 적용

문법 검사만 먼저 할 수 있습니다. 이 검사는 방화벽을 바꾸지 않습니다.

```sh
scripts/tailscale-pf/load.sh --self-test
scripts/tailscale-pf/set.sh --self-test
scripts/tailscale-pf/unset.sh --self-test
plutil -lint scripts/tailscale-pf/com.chann.tailscale-ssh-vnc.plist
```

적용은 관리자 암호를 묻습니다. `yes`를 입력해야 바뀝니다.

```sh
scripts/tailscale-pf/set.sh
```

확인 질문을 건너뛰려면 `scripts/tailscale-pf/set.sh --yes`입니다.

하는 일은 다음과 같습니다.

1. `/etc/pf.conf`에 앵커를 넣을 자리를 먼저 정합니다. 이미 불러오는 줄이 있으면 그 파일은 그대로 둡니다. `anchor "com.apple.internet-sharing"`이 있으면 그 위에, 없으면 `anchor "com.apple/*"` 위에 넣습니다. 둘 다 없으면 여기서 멈추고 시스템 파일은 바꾸지 않습니다.
2. `pf.anchor`, `load.sh`, LaunchDaemon plist를 시스템 경로에 복사합니다.
3. 내용을 바꿀 때는 처음 한 번 `/etc/pf.conf.before-set-tailscale-ssh-vnc`로 복사해 둡니다. 이미 백업이 있으면 덮어쓰지 않습니다.
4. `load.sh`로 문법을 확인하고 pf를 다시 읽습니다. 커널 규칙이 맞으면 `tailscale-pf: loaded.`를 출력합니다. 그 다음 데몬을 등록합니다.

시스템 설정의 원격 로그인과 화면 공유 스위치는 바꾸지 않습니다. 그 서비스가 꺼져 있으면 포트를 허용해도 접속은 되지 않습니다.

## 해제

```sh
scripts/tailscale-pf/unset.sh --self-test
scripts/tailscale-pf/unset.sh
```

데몬을 끄고 `/etc/pf.conf`에서 앵커 줄을 지운 다음 pf를 다시 읽습니다. 규칙 파일, `load.sh`, plist도 지웁니다. 로그 파일은 남깁니다. pf 자체는 끄지 않습니다. 응용 프로그램 방화벽이 pf를 계속 사용합니다. `pfctl -d`는 쓰지 않습니다.

해제 뒤 22, 5900, 3283은 이 맥까지 패킷이 닿는 곳이면 다시 받을 수 있습니다. 같은 LAN이 포함됩니다. 공유기가 그 포트를 이 맥으로 넘기고 있다면 인터넷에서도 닿습니다.

처음 한 번 `/etc/pf.conf.before-unset-tailscale-ssh-vnc`에 해제 직전 내용을 복사합니다.

## 확인

```sh
sudo pfctl -s info
sudo pfctl -a com.chann.tailscale-ssh-vnc -sr
```

`Status: Enabled`이면 pf가 켜져 있습니다. 앵커 출력은 pass 18줄과 block 6줄입니다. 22, 5900, 3283 외의 포트가 보이면 이 앵커가 아닙니다. `load.sh`는 같은 확인을 하고 `tailscale-pf: loaded.`로 끝냅니다.

디스크의 `pf.anchor`를 고친 것만으로는 커널 규칙이 바뀌지 않습니다. `set.sh`가 파일을 복사한 뒤 `load.sh`로 다시 읽습니다. 재부팅 때도 데몬이 `load.sh`를 실행합니다.

## 이 필터 밖에 있는 것

이 앵커는 22, 5900, 3283만 봅니다. Microsoft RDP인 3389도, 443, 5000, 7000, 88처럼 모든 인터페이스에서 듣고 있는 다른 포트도 그대로입니다.

`100.64.0.0/10`은 우리 tailnet만의 목록이 아닙니다. Tailscale을 쓰는 모든 네트워크가 이 대역을 씁니다. 규칙은 패킷이 Tailscale 인터페이스로 들어왔는지도 보지 않습니다. 공개 인터넷에서 출발지를 이 대역으로 속여 SSH 연결을 끝내려면 응답이 Tailscale 경로로 돌아가야 하므로, 그 시도는 이어지지 않습니다. 같은 LAN에서 출발지를 속이는 경우까지 막고 싶다면 통과 규칙에 인터페이스를 지정하면 됩니다. macOS에서는 그 인터페이스 이름이 재부팅 뒤에 바뀔 수 있어서, 지금 규칙은 주소만 봅니다.

## 파일

| 저장소 | 맥에 복사되는 위치 | 권한 |
| --- | --- | --- |
| `pf.anchor` | `/etc/pf.anchors/com.chann.tailscale-ssh-vnc` | `root:wheel`, `644` |
| `load.sh` | `/Library/Application Support/tailscale-pf/load.sh` | `root:wheel`, `755` |
| `com.chann.tailscale-ssh-vnc.plist` | `/Library/LaunchDaemons/com.chann.tailscale-ssh-vnc.plist` | `root:wheel`, `644` |
| `set.sh`가 고치는 줄 | `/etc/pf.conf` | `root:wheel`, `644` |
