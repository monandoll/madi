# 영상 출처 — 쌤 채널 · 시험용 영상 링크 (2026-09-29)

영상 파일은 **커밋하지 않는다** (`spike/source/` 는 `.gitignore`). 이 문서는 어디서 받았는지 · 다시 받는 법만 남긴다.
받을 때는 **H.264(avc1)** 로 받는다 — AVFoundation 은 유튜브 AV1 · VP9 을 못 푼다:

```
yt-dlp -f "bv*[vcodec^=avc1]+ba[ext=m4a]" --merge-output-format mp4 -o "spike/source/%(id)s.%(ext)s" <링크>
```

## 1. 쌤 (크리에이터) — **기준 영상**

| | 링크 |
|---|---|
| 유튜브 채널 | https://www.youtube.com/@physila_sh (숏폼 https://www.youtube.com/@physila_sh/shorts) — 2026-09-29 기준 숏폼 132편, 긴 영상 없음 |
| 인스타그램 | https://www.instagram.com/physila_sh/ (릴스 https://www.instagram.com/physila_sh/reels/) — 채널 소개에 적힌 계정 |

- 인스타 릴스는 로그인 없이 목록 · 다운로드가 안 된다. 유튜브 숏폼과 대부분 같은 영상이라 **유튜브에서 받는다**
- 쌤 촬영 **원본**(편집 전)은 아직 없다. 아래는 전부 쌤이 직접 편집해 올린 **완성본** — 쌤이 어떻게 편집하는지의 기준이다

### 1-1. 잰 10편 (`spike/source/<id>.mp4` · 프레임 `reference/<id>_*.jpg`)

자막 크기 · 위치 · 분절(§9), 사람 크기(G1 · G2), 훅(G8), 컷 호흡(`docs/findings/2026-09-29-cut-breath.md`)을 전부 이 10편으로 쟀다.

| id | 올린 날 | 길이 | 내용 | 링크 |
|---|---|---|---|---|

| `59HP4jxLFeA` | 2026-07-17 | 0:23 | 골반 교정 — 동작 몽타주 (말 14%) | https://www.youtube.com/shorts/59HP4jxLFeA |
| `EDpBGkaNJmU` | 2026-08-03 | 0:19 | 골반이 틀어져있다면, 이 동작 안되실걸요? | https://www.youtube.com/shorts/EDpBGkaNJmU |
| `8DF9jrxQM4U` | 2026-08-05 | 0:18 | 사람들은 잘 모르는 골반교정 필수동작 | https://www.youtube.com/shorts/8DF9jrxQM4U |
| `nCshtY04NiY` | 2026-08-26 | 0:19 | 다리 교정할 때 98%는 이거 모르고 후회 | https://www.youtube.com/shorts/nCshtY04NiY |
| `xaUpqHAQjo4` | 2026-08-27 | 0:26 | 다리가 무겁다던 엄마, 이젠 매일 해달래요 | https://www.youtube.com/shorts/xaUpqHAQjo4 |
| `L469kzZZe1E` | 2026-09-01 | 0:26 | 팔뚝이 두꺼워 보이는 게 살 때문이 아니라 | https://www.youtube.com/shorts/L469kzZZe1E |
| `UzemW44yzSo` | 2026-09-03 | 0:23 | 운동해도 납작한 사람들의 공통점 | https://www.youtube.com/shorts/UzemW44yzSo |
| `lzDW-9ITfWU` | 2026-09-07 | 0:13 | 허리 안 만졌는데 왜 내려가 | https://www.youtube.com/shorts/lzDW-9ITfWU |
| `RnP7b0JFWj4` | 2026-09-17 | 0:27 | 종아리가 딴딴하신 분들은 이거 안되실걸요 | https://www.youtube.com/shorts/RnP7b0JFWj4 |
| `Wp7dWPpiFew` | 2026-09-24 | 0:19 | 자기 전 단 5분이면 다리가 바뀝니다 | https://www.youtube.com/shorts/Wp7dWPpiFew |

### 1-2. 채널 숏폼 전체 132편 (최신 순) — 더 재야 할 때 여기서 고른다

`★` 는 1-1 에서 잰 것. 제목은 유튜브가 자동 번역해 준 대로다.

- https://www.youtube.com/shorts/iIFIFsQAXbA — 🫢Miraculous shoulder transformation in just 3 tries#ShoulderPain
- ★ https://www.youtube.com/shorts/Wp7dWPpiFew — 🦵Just 5 minutes before bed can transform your legs#LowerBodyEdema #Pos
- https://www.youtube.com/shorts/YQEFOiVE2Fo — A Lifesaver for Mask Wearers..🙏#Ad
- ★ https://www.youtube.com/shorts/RnP7b0JFWj4 — 🦵If your calves are rock-hard, you probably can't do this... #PostureC
- ★ https://www.youtube.com/shorts/lzDW-9ITfWU — 🫢I didn't even touch my lower back... why does it bend further..? #Pos
- ★ https://www.youtube.com/shorts/UzemW44yzSo — 😱 Why your glutes still look flat despite working out..? #PostureCorre
- ★ https://www.youtube.com/shorts/L469kzZZe1E — 🫢Is my arm fat actually not because of weight…? #AnteriorGlide #Postur
- ★ https://www.youtube.com/shorts/xaUpqHAQjo4 — 🦵My mom used to say her legs felt heavy, now she asks me to do this ev
- ★ https://www.youtube.com/shorts/nCshtY04NiY — 98% of people regret not knowing this when fixing their legs🤦‍♀️#Postu
- https://www.youtube.com/shorts/PtFn3_LyBc4 — 🔥3-Minute Gua Sha Routine to Slim Your Calves by 3cm #CalfMassage
- https://www.youtube.com/shorts/OCcqmeywn8o — How to Find Your Abs in Just 6 Moves #AbdominalMassage
- https://www.youtube.com/shorts/EQ24HXmkYAc — 💆‍♀️It’s actually this easy to get glowing skin..?#Guasha#FaceContouri
- https://www.youtube.com/shorts/82iiQ6ujMyU — 📩Calling everyone who can't lose belly fat no matter how much they exe
- https://www.youtube.com/shorts/k1ayvUzo7yQ — 🖐️5 Minutes to Tighten Your Jawline🔥#Contouring #shorts
- ★ https://www.youtube.com/shorts/8DF9jrxQM4U — 🚨The Essential Pelvic Correction Move Most People Don't Know?#rehab#sh
- ★ https://www.youtube.com/shorts/EDpBGkaNJmU — 🚨If your pelvis is misaligned, you probably can't do this move. #physi
- https://www.youtube.com/shorts/HHLzEPKtHXk — 🫢The Best Way to Get Rid of That Hump on Your Neck #PhysicalTherapist 
- https://www.youtube.com/shorts/i036R8fqLQw — 🥼It’s not a procedure, it’s just natural shoulders#physiotherapist #sh
- https://www.youtube.com/shorts/YxcKrruTVZc — 🫢Your face can change in 30 seconds? #Contour #Massage #physiotherapis
- https://www.youtube.com/shorts/4T63BIVj0-Y — 🎾💪How to get rid of tennis elbow in 30 seconds? #physiotherapist #shor
- ★ https://www.youtube.com/shorts/59HP4jxLFeA — 🏋️You can fix your tilted pelvis in just 3 moves..?#physiotherapist #s
- https://www.youtube.com/shorts/55EFCI8uzuQ — There’s no way you can’t last for a minute, right…?🫢#physiotherapist #
- https://www.youtube.com/shorts/sCeNXh0uSNY — 💻A way to hack your brain to fall asleep...?🫢 #physiotherapist #shorts
- https://www.youtube.com/shorts/myLEr8I1CiA — 몰랐지?#physiotherapist #shorts
- https://www.youtube.com/shorts/aQq_iZc29Rg — 🤫The stretches my lower back actually needs #physiotherapist #shorts
- https://www.youtube.com/shorts/i1rHdNHdMv8 — 🫢You can get a celebrity-fit just by stretching this one spot??#physio
- https://www.youtube.com/shorts/ZaB_EFe2dhY — 🫢Your knees stick out? #physiotherapist #shorts
- https://www.youtube.com/shorts/xniRql5Qe1A — 🤤My back is melting away… #physiotherapist #shorts #physicaltherapist
- https://www.youtube.com/shorts/nYsMZoVOY9s — The 10-Minute Life-Changing Miracle Routine⭐️#physiotherapist #shorts
- https://www.youtube.com/shorts/IE1s_IkS3F8 — 🕶️Remember this if you're in your 30s and want to transform your body!
- https://www.youtube.com/shorts/9n2wP0m-9EQ — ⭐️Changed how I lie down and my neck popped back into place..⭐️#physio
- https://www.youtube.com/shorts/htz4UF_yOao — 🆘What stage of tech neck do I have..? Check in 10 seconds🆘#physiothera
- https://www.youtube.com/shorts/_J6FBKV4jFU — 🔥The Easiest Way to Get a Super Slim Waist🕶️#physiotherapist #shorts
- https://www.youtube.com/shorts/SoKCfElpJ54 — Great value mental discipline 🧎‍➡️ #physiotherapist #shorts
- https://www.youtube.com/shorts/8b3Go1u22KY — 🤫Lubricate your stiff shoulders with "just this one move"🕶️#physiother
- https://www.youtube.com/shorts/ZiAnbeInXus — 🚨Struggling with tech neck, rounded shoulders, or a hunched back? Fix 
- https://www.youtube.com/shorts/4wNBe46atHI — Starting with an absolute, 100% real review….#physiotherapist #shorts
- https://www.youtube.com/shorts/p2I9DyFabvo — 🙊 This is the first time in my life my back has been this straight.. #
- https://www.youtube.com/shorts/9XcRvdNE9xk — 🏋️‍♀️ 운동할 때 테이핑 많이 쓰시는 분들, 바로 집중🏋️ #티에스테이핑 #스포츠테이프 #키네시오로지테이프 #테이핑 #광고
- https://www.youtube.com/shorts/tVR6ilOSAP4 — 🦶 If you have heel pain, try resolving it in just 4 sessions 🙊 #Physic
- https://www.youtube.com/shorts/9rIqvGIEWss — 🦵 Making straight legs? That's so simple! 🤔 #PhysicalTherapist #physio
- https://www.youtube.com/shorts/NcZsv6Do4IQ — 해부학은 춤으로 배워야해!💃#물리치료사 #anatomy
- https://www.youtube.com/shorts/ngWiR4VLAn4 — 🙊 I told you, my neck popped and went back in after doing this! 🐢 #phy
- https://www.youtube.com/shorts/PDbjZYIjuXU — 🐢How to permanently get rid of forward head posture🐢 #physiotherapist 
- https://www.youtube.com/shorts/MloDQtdHrDI — 😎 Celebrities do “this” for facial care… .? #physiotherapist #shorts
- https://www.youtube.com/shorts/AcmfHwH5km4 — 환자분이 너무 맛있는 썰을 들고왔다…🍿#물리치료사 #shorts
- https://www.youtube.com/shorts/xs94aW8Dvig — 👶 You can look 3 years younger in just 3 minutes…? #physiotherapist #p
- https://www.youtube.com/shorts/xFCh6_IuqL0 — Ganbare with Yoo Min-sang~!!👏👏 #NewMinSang #YooMinSang #shorts
- https://www.youtube.com/shorts/P1dAD_LVEZ0 — Wow… I thought my back was melting… … .#physiotherapist #shorts
- https://www.youtube.com/shorts/TWY039X1zkU — 😱 If this sags, wrinkles will increase 30 times?😱 #physiotherapist #sh
- https://www.youtube.com/shorts/UJqQ-MlT0Gs — Give it a try and follow along consistently for 1 minute a day 📝 Your 
- https://www.youtube.com/shorts/tDi-Pitddco — 정말로? #물리치료사 #공감 #shorts
- https://www.youtube.com/shorts/P7bh3k2l8FQ — 🕶️단 1분만 투자하면 얼굴비대칭이 맞춰진다고?#physiotherapist #shorts
- https://www.youtube.com/shorts/uos7NXS5K8I — 🥢젓가락하나로 “하루 1분만” 따라해보세요🥢#physiotherapist #물리치료사 #shorts
- https://www.youtube.com/shorts/ffbrHw4Xxi4 — 내가 다 낫게 해줄게..🔫❤️#physiotherapist #물리치료사 #shorts
- https://www.youtube.com/shorts/fchuu57J7I0 — 👃Your Go-To Guide for a Nose Job Without Surgery👃#physicaltherapist #p
- https://www.youtube.com/shorts/3mSyL1RDtas — $9,000 for a herniated neck disc surgery.#physiotherapist #physicalthe
- https://www.youtube.com/shorts/KlRZ0hhgKkg — 🐘If you have elephant calves, you must try this🐘#physicaltherapist #ph
- https://www.youtube.com/shorts/TclxymVcp9g — 🫧You have a hunched back and you're not doing this?🫧#physiotherapist #
- https://www.youtube.com/shorts/NM_Bn7u-FEE — 🍑You can get a hip filler look just like this?🍑#physiotherapist #short
- https://www.youtube.com/shorts/XIoH--uupp4 — 📩Try this while sitting and your shoulders will melt away..🙊#physicalt
- https://www.youtube.com/shorts/yUY3HRRuIJg — ⭐️Get Perfectly Defined Square Shoulders with This One Move⭐️#physioth
- https://www.youtube.com/shorts/ov7BX1sqArs — 🙏If your body is hunched forward, this one move is all you need#physic
- https://www.youtube.com/shorts/v9k_gacC2TQ — 📩Try this when your lower back feels stiff! You'll be amazed at how re
- https://www.youtube.com/shorts/qkHZ8WNR1kw — Make a promise with your therapist #physiotherapist #physiotherapist #
- https://www.youtube.com/shorts/R_ygw-G-2hg — 💪If your shoulders and arms are stiff, please just try this once...🙏🥺#
- https://www.youtube.com/shorts/p3jNXwYgxWU — ⭐️Pressure points to flush out facial puffiness ⭐️#physiotherapist #ph
- https://www.youtube.com/shorts/hjhTzTtxSbE — Ah.. now the blood is finally flowing through my legs..🩸👍#PhysicalTher
- https://www.youtube.com/shorts/q_ULW3IuZxU — 🏋️Straighten Out Your Hunched Posture🏋️#PhysicalTherapist #physiothera
- https://www.youtube.com/shorts/ac0bmFyRs1Q — 👂The Incredible Changes That Happen When You Pull Your Ears👂#PhysicalT
- https://www.youtube.com/shorts/pk_vOTCqJG0 — The Best Position to Clear Pelvic Congestion⭐️#PhysicalTherapist #phys
- https://www.youtube.com/shorts/753U1Vo377k — 💪No More Hip Popping‼️How to Fix Your Pelvis at Home #physiotherapist 
- https://www.youtube.com/shorts/sbsOjjOsEbU — From now on, everyone will only be looking at your eyes.. #physiothera
- https://www.youtube.com/shorts/y2ENH-5Uw8A — ⭐️👁️How to Get Idol-Like Sparkling Eyes👁️⭐️#physiotherapist #shorts
- https://www.youtube.com/shorts/2IN5q8ay8NM — 📌-2-Inch Waist-Slimming Stretch📌
- https://www.youtube.com/shorts/R4WS7SCrF_0 — 🔥The bow-legged correction method going viral abroad🔥#physiotherapist 
- https://www.youtube.com/shorts/cUylz5KCuVs — 이잉 해줘#physiotherapist #물리치료사 #shorts
- https://www.youtube.com/shorts/JT-BwDaBKGU — Try this 60 times before or after bed👍Your lower back will feel instan
- https://www.youtube.com/shorts/M3rw1ABiAAE — 💌A video for my constipated friends💌Still have a bloated belly even af
- https://www.youtube.com/shorts/LGFy8u33HrQ — 어깨 테이핑 꿀팁 남한테 부탁하기#물리치료사 #physiotherapist #asmr #shorts
- https://www.youtube.com/shorts/oIONzZTli00 — 동그라미에 손대보세용 put your finger on the circles #physiotherapist #shorts
- https://www.youtube.com/shorts/Ogm9Z5JrcXI — 💡This is all you need to realign your body🍀#physiotherapist #physicalt
- https://www.youtube.com/shorts/xakzfTZSm_A — 💡Try this to see if your body is misaligned💡#physiotherapist #physical
- https://www.youtube.com/shorts/R636vig2AGs — 내가 엄청난거 보여주까?#physiotherapist #shorts
- https://www.youtube.com/shorts/RatRgwVr0Pc — 💡Send this to your short friends who need a height boost💡#physiotherap
- https://www.youtube.com/shorts/XnPnFUOQPL8 — Telling the story of the taping I was sponsored for earlier #physiothe
- https://www.youtube.com/shorts/9cuu3nWt8UM — 📍30초 이상 버티지못하면 코어불량#physiotherapist #물리치료사 #코어운동 #shorts
- https://www.youtube.com/shorts/P87U0JO6ehk — 🐢If you have tech neck, you have to try this🐢#physiotherapist #physica
- https://www.youtube.com/shorts/Y6dxPhq_sqE — 거북목이라면 “이게”닿지 않을겁니다‼️#물리치료사 #physiotherapist #거북목 #shorts
- https://www.youtube.com/shorts/OFvrjPMq1Jw — Urgent finger ASMR #physiotherapist #physicaltherapist #asmr #shorts
- https://www.youtube.com/shorts/5uCXuTrBLFc — Knee Pain Relief ASMR #physiotherapist #physicaltherapist #asmr #rehab
- https://www.youtube.com/shorts/61NBlsB6ro0 — 💡Exercises to Do with Parents Who Have Herniated Discs💡#physiotherapis
- https://www.youtube.com/shorts/2H4JXTiei5c — I told you to tape your ankle #physiotherapist #physicaltherapist #tap
- https://www.youtube.com/shorts/M5Tho7fof8g — 손목 테이핑 asmr#physiotherapist #물리치료사 #asmr #shorts
- https://www.youtube.com/shorts/-13fVMcMmyk — 💡Send this to someone with misaligned hips💡 Try this move just 10 time
- https://www.youtube.com/shorts/lx9YmzMdcC4 — 💡Send this to someone with pelvic misalignment💡If your pelvis is misal
- https://www.youtube.com/shorts/wFRw_0LI5Q4 — 굽은등 쫙펴주는 운동인 쉐이칸샹쉐이칸샹#physiotherapist #물리치료사 #재활운동 #shorts
- https://www.youtube.com/shorts/0x79jdEmkCE — ✨요가링 다이어트?✨ 아랫배가 톡튀어나와있다구?❓요가링으로 내장과 복부근육의 이완으로 아랫배가 쏙 들어가요#shorts #ph
- https://www.youtube.com/shorts/B_g9Hi8Jwo4 — 15초로 배우는 해부학 🦴15sec anatomy🦴#물리치료사 #physiotherapist #shorts
- https://www.youtube.com/shorts/w8RPN4qfsSg — 🌤️🌸답변할때 굳이 말로 해야되나여🌸🌤️#physiotherapist #물리치료사 #shorts
- https://www.youtube.com/shorts/xcuGwgaH0_w — 🦴15초 해부학 15sec anatomy🦴#physiotherapist #물리치료사 #shorts
- https://www.youtube.com/shorts/J_HlluCPBWk — 물리치료사가 보장하는 초간단 무릎운동✨✨👍 #shorts #physiotherapist #물리치료사
- https://www.youtube.com/shorts/g4op4rnrO4A — 시골 소녀는 아직 서울이 낯설어요 #shorts
- https://www.youtube.com/shorts/wqgXxN-fB1U — 잔말말고 에어컨 파워냉방으로 틀어 #물리치료사 #physiotherapist #shorts
- https://www.youtube.com/shorts/1qXnE_Uwg_c — 좁아지는 손목관절?손목통증?이걸로 해결✨#physiotherapist #물리치료사 #shorts
- https://www.youtube.com/shorts/pcHo9QcHDa4 — ✨툭 튀어나온 목! 뒤로 넣는비법✨#물리치료 #물리치료사 #재활운동 #거북목 #shorts
- https://www.youtube.com/shorts/LQm9TH-Wc4U — 갓생러의 4가지 직업 어떤게 가장 잘어울리나요? #물리치료사 #트레이너 #필라테스강사 #콘텐츠크리에이터 #shorts
- https://www.youtube.com/shorts/xb8ESnYV_3o — 🍞빵먹방아니예요🍞등허리 뻐근하신분들!이거따라해보세요✨이 한끗‼️차이로 스트레칭이 달라집니다👍#물리치료사 #physiothera
- https://www.youtube.com/shorts/v7XGHa7WUvE — 🍀If your neck cracks, try this out‼️ #physiotherapist #physicaltherapi
- https://www.youtube.com/shorts/oSokt5oJNGs — 운동할 시간없는 직장인들 학생들은 따라해보세요 #물리치료사 #physiotherapist #shorts
- https://www.youtube.com/shorts/g-xCe4EnWHg — 전지적 떨어진 스펀지 시점 #shorts #물리치료사 #physiotherapist
- https://www.youtube.com/shorts/2BpYgRnWh8o — 안좋은 수면자세 알려줄게✅ 난 먗번째 해당되는지 체크‼️
- https://www.youtube.com/shorts/j8Xr_5vpda0 — 부모님  #도수치료 #물리치료 #physiotherapy #physiotherapist #chill #chillguy
- https://www.youtube.com/shorts/Sz5-qTjHCFM — O자 다리이신분들 이거 왜 안하세요❓🤔일자다리 즉각생성/필라테스하는물리치료사#shorts
- https://www.youtube.com/shorts/5l31vfDpzP4 — 이거할때마다 기린되는것같아..🤸완전 시원한 목스트레칭👍🔥/필라테스하는물리치료사수현쌤#shorts
- https://www.youtube.com/shorts/kurYmHGso6A — 효과가 이렇게 확실할수없다…….🔥고관절기름칠🔥/필라테스하는물리치료사 수현쌤#shorts
- https://www.youtube.com/shorts/c11jA2LKcgA — 🌟아무도 몰랐던 🌟두통 해결방법🤸‍♀️🚨/필라테스하는물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/-rEPIatd9Zc — 발등&정강이앞 통증❓즉각해결스트레칭💪👍‼️/필라테스하는물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/MGmLeIrdQoU — 누가 내 손가락에 기름칠했냐‼️‼️/손가락통증/방아쇠수지/triggerfinger #shorts
- https://www.youtube.com/shorts/P0WsH3wkQsk — 🌟저는 이렇게 합니다🌟/scapular movement#shorts
- https://www.youtube.com/shorts/9HbY5Mt6DDs — 발목통증?너무 간단히 해결되는데❓/필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/q8pqOxu43OM — 등 뒤로 쫙쫙펴주기👍맨몸으로도 가능👊 /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/-PeyVlbTK1s — 고관절기름칠❓이거한번해봐‼️ /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/LczSFy-ZUiA — 고관절&허리&흉추 셀프가동성확인🔥 /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/RDrEbIkxo0U — 고작 의자하나로 어깨통증 없애기/필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/AnebV-cTgwg — 허리통증 없애주는 기적의운동🔥 /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/XlFd51tTgJY — 나랑 눈마주치면 치료하는거다
- https://www.youtube.com/shorts/jYG1JGS6_5g — 손바닥저림&손저림/median nerve /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/mjn44Ka0sZc — 1&2번째 손가락 저림&손저림/radialnerve /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/ZfFrkxwir0k — 4&5번째 손가락 저림&손저림&팔저림 해결가능?가능❗️ /필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/58lqTypdd-w — 목어깨통증&두통 단번에 해결🔥/필라테스하는 물리치료사 수현쌤 #shorts
- https://www.youtube.com/shorts/Zszw42Fozr0 — 허리통증 맨손운동으로 해결💪🔥/필라테스하는 물리치료사 수현쌤 #shorts

## 2. 시험용 (쌤 영상 아님 — **대용**)

쌤 촬영 원본이 없어서 리프레이밍 · 파이프라인 · 부하를 다른 채널 영상으로 시험했다. **품질 기준으로 쓰지 않는다** (기준은 1절).

### 2-1. 16:9 운동 · 재활 롱폼 (`spike/source/raw/<id>.mp4` — 앞 150초만 받음, 1~5단계 대용)

| id | 채널 | 원본 길이 | 링크 |
|---|---|---|---|
| `6U6Qp35FQaM` | 피지오푸 (@physiopooh) — 도수치료 실습 | 10:43 | https://www.youtube.com/watch?v=6U6Qp35FQaM |
| `fuTjB-F6-DE` | 빵느 (@bbangneu) — 필라테스 개인레슨 | 26:41 | https://www.youtube.com/watch?v=fuTjB-F6-DE |
| `NOCXAZE8XdQ` | BND STUDIO (@bodyndance_bndstudio) — 30분 전신 스트레칭 | 28:30 | https://www.youtube.com/watch?v=NOCXAZE8XdQ |
| `uw1aUHnMfo8` | Ram PT (@pt3885) — 10분 서서 하는 전신 스트레칭 | 10:20 | https://www.youtube.com/watch?v=uw1aUHnMfo8 |
| `VtFNkL7oAWM` | 서울재활병원TV — 편마비 상체 운동 | 18:33 | https://www.youtube.com/watch?v=VtFNkL7oAWM |
| `zV4hh3M5eGI` | 빵느 (@bbangneu) — 60분 전신운동 | 57:31 | https://www.youtube.com/watch?v=zV4hh3M5eGI |

### 2-2. 부하 테스트 (통째로 받음 — `~/Downloads/madi-test-videos/`)

| 파일 | 채널 | 링크 |
|---|---|---|
| `10분-uw1aUHnMfo8.mp4` (1080p) | Ram PT (@pt3885) | https://www.youtube.com/watch?v=uw1aUHnMfo8 |
| `30분-yh6hNVlbUbU.mp4` (1080p · 24fps · 31:05) | MAKEDANDAN 메이크단단 (@MAKEDANDAN) | https://www.youtube.com/watch?v=yh6hNVlbUbU |
| `1분-stage4-standin.mov` | 위 `uw1aUHnMfo8` 앞 60초 | — |
| `2분30초-<id>.mp4` ×6 | 2-1 과 같은 파일 | — |

### 2-3. 세로 대용 (`spike/source/vert/` — 1단계, `docs/findings/2026-09-26-vertical-substitutes.md`)

| id | 출처 · 라이선스 | 링크 |
|---|---|---|
| `mk32809` `mk40246` `mk40787` `mk43785` `mk4942` `mk5057` `mk5065` `mk52079` `mk52080` | mixkit.co (Mixkit Free License — 상업 이용 가능 · 표기 불요) | https://mixkit.co/free-stock-video/ 에서 번호로 찾는다 |
| `KTNay8unSK4` | Cali Cheer Show — CC-BY | https://www.youtube.com/watch?v=KTNay8unSK4 |

### 2-4. CC-BY 짧은 클립 (`spike/source/cc/` — G2 측정)

| id | 채널 | 링크 |
|---|---|---|
| `CCXaf0xLCKA` | No Copyright - Video Library | https://www.youtube.com/watch?v=CCXaf0xLCKA |
| `CHToMK69xiU` | NoCopyrightVideos | https://www.youtube.com/watch?v=CHToMK69xiU |
| `EjwQjsTQpPc` | Motion | https://www.youtube.com/watch?v=EjwQjsTQpPc |
| `Ek8lYHJ1eBk` | Stock Unlimited | https://www.youtube.com/watch?v=Ek8lYHJ1eBk |
| `qomCoWoSUD8` | Stock Unlimited | https://www.youtube.com/watch?v=qomCoWoSUD8 |
| `wqCvuhfRXRU` | Motion | https://www.youtube.com/watch?v=wqCvuhfRXRU |

`spike/source/IMG_6022.mov` (헬스장 2인 · 판정 불가 회귀 사례)는 아이폰 촬영본 이름이다 — 출처 링크 없음.

