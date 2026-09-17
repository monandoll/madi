import { useEffect, useState } from 'react';
import QRCode from 'qrcode';

/**
 * QR 그림. 폰 카메라로 찍으면 그 주소가 열린다.
 * 색은 토큰을 그대로 쓴다 (검정 대신 text, 흰 배경).
 */
export function Qr({ value, size = 168, className }: { value: string; size?: number; className?: string }) {
  const [src, setSrc] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    QRCode.toDataURL(value, { width: size * 2, margin: 1, errorCorrectionLevel: 'M', color: { dark: '#1C2127', light: '#FFFFFF' } })
      .then((url) => alive && setSrc(url))
      .catch(() => alive && setSrc(null));
    return () => {
      alive = false;
    };
  }, [value, size]);
  return (
    <div className={`flex flex-none items-center justify-center overflow-hidden rounded-thumb border border-line bg-surface ${className ?? ''}`} style={{ width: size, height: size }} data-testid="qr">
      {src && <img src={src} alt="QR" width={size} height={size} style={{ width: size, height: size }} />}
    </div>
  );
}
