"""Windows stand-in for face_box.swift (macOS Vision): OpenCV's face detector on the same frames.
Usage: python face_box_cv.py <frame.jpg>...  -> one line per frame: "x y w h" (0..1, top-left origin) or "none".
OpenCV lives in ~/reels/.venv (doctor.sh installs it); without it face_box.py keeps the default face zone."""
import _win  # noqa: F401  (Windows: UTF-8 mode, finds ~/reels/.venv)
import sys
import cv2

det = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
for f in sys.argv[1:]:
    img = cv2.imread(f)
    if img is None: print("none"); continue
    h, w = img.shape[:2]
    faces = det.detectMultiScale(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), scaleFactor=1.1, minNeighbors=6, minSize=(w // 8, w // 8))
    if len(faces) == 0: print("none"); continue
    x, y, fw, fh = max(faces, key=lambda r: r[2] * r[3])   # the biggest face is the speaker
    print(f"{x / w:.4f} {y / h:.4f} {fw / w:.4f} {fh / h:.4f}")
