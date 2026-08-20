# Build FaceSwapCam iOS บน GitHub Actions

โปรเจกต์นี้เตรียมไว้สำหรับ Build iOS จาก Windows โดยใช้ GitHub Actions macOS runner แล้วสร้าง `FaceSwapCam-unsigned.ipa` สำหรับนำไป sign/install ด้วย AltServer

## ใช้งาน
1. เปิดโฟลเดอร์นี้ใน VS Code แล้วรัน `flutter pub get`
2. Push ทั้งโฟลเดอร์ขึ้น GitHub branch `main`
3. ไปที่ GitHub > Actions > Build FaceSwap iOS IPA > Run workflow
4. รอ job `build-ios` เป็นสีเขียว
5. ที่หน้า Summary > Artifacts ดาวน์โหลด `FaceSwapCam-iOS-unsigned`
6. แตก ZIP จะได้ `FaceSwapCam-unsigned.ipa`
7. ใช้ AltServer บน Windows sign/install ลง iPhone

## iOS configuration ที่ workflow สร้างให้
- iOS deployment target 15.0
- Camera permission
- Microphone permission
- Photo Library permission
- Local Network permission
- permission_handler macros: CAMERA / MICROPHONE / PHOTOS
- CocoaPods mode สำหรับ plugins

หมายเหตุ: IPA ที่ได้จาก Actions เป็น unsigned โดยตั้งใจ เพื่อให้ AltServer sign ด้วย Apple Account ฟรีภายหลัง
