import { datadogRum } from '@datadog/browser-rum';
import { useEffect } from 'react';

// Pattern: RUM user identification — track sessions by user
// Adapt: call after your authentication flow resolves
export default function UserIdentification({ userId, email }: { userId: string; email: string }) {
  useEffect(() => {
    datadogRum.setUser({ id: userId, email, name: email.split('@')[0] });
  }, [userId, email]);

  return null;
}
