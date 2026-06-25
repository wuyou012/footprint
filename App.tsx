import { StatusBar } from 'expo-status-bar';

import { RecordScreen } from './src/screens/RecordScreen';

export default function App() {
  return (
    <>
      <RecordScreen />
      <StatusBar style="auto" />
    </>
  );
}
