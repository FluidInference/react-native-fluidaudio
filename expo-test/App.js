import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, View } from 'react-native';
import { useEffect, useState } from 'react';
import { getSystemInfo } from '@fluidinference/react-native-fluidaudio';

export default function App() {
  const [status, setStatus] = useState('Loading...');
  const [info, setInfo] = useState(null);

  useEffect(() => {
    async function test() {
      try {
        setStatus('Calling getSystemInfo...');
        const result = await getSystemInfo();

        setInfo(result);
        setStatus('Success!');
      } catch (error) {
        setStatus(`Error: ${error.message}`);
        console.error('FluidAudio error:', error);
      }
    }
    test();
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>FluidAudio Expo Test</Text>
      <Text style={styles.status}>{status}</Text>
      {info && (
        <View style={styles.infoBox}>
          <Text style={styles.infoText}>Platform: {info.platform}</Text>
          <Text style={styles.infoText}>Apple Silicon: {info.isAppleSilicon ? 'Yes' : 'No'}</Text>
          <Text style={styles.infoText}>Summary: {info.summary}</Text>
        </View>
      )}
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
  },
  status: {
    fontSize: 16,
    color: '#666',
    marginBottom: 20,
    textAlign: 'center',
  },
  infoBox: {
    backgroundColor: '#f0f0f0',
    padding: 20,
    borderRadius: 10,
  },
  infoText: {
    fontSize: 14,
    marginBottom: 5,
  },
});
