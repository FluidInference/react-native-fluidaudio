/**
 * Example React Native App using FluidAudio
 *
 * This is a reference implementation showing how to use
 * the react-native-fluidaudio package.
 */

import React, { useEffect, useState, useCallback } from 'react';
import {
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  ActivityIndicator,
} from 'react-native';

import {
  FluidAudio,
  ASRManager,
  VADManager,
  DiarizationManager,
  TTSManager,
  onModelLoadProgress,
  cleanup,
  type SystemInfo,
  type ASRResult,
  type ModelLoadProgressEvent,
} from 'react-native-fluidaudio';

const App = () => {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadingStatus, setLoadingStatus] = useState('');
  const [result, setResult] = useState<string>('');

  // Manager instances
  const [asr] = useState(() => new ASRManager());
  const [vad] = useState(() => new VADManager());
  const [diarizer] = useState(() => new DiarizationManager());
  const [tts] = useState(() => new TTSManager());

  // Load system info on mount
  useEffect(() => {
    FluidAudio.getSystemInfo().then(setSystemInfo);

    // Subscribe to model loading progress
    const subscription = onModelLoadProgress((event: ModelLoadProgressEvent) => {
      setLoadingStatus(`${event.type ?? 'Model'}: ${event.status} (${event.progress}%)`);
    });

    return () => {
      subscription.remove();
      cleanup();
    };
  }, []);

  // Initialize ASR
  const initializeASR = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      const initResult = await asr.initialize();
      setResult(`ASR initialized in ${initResult.compilationDuration.toFixed(2)}s`);
    } catch (error) {
      setResult(`Error: ${(error as Error).message}`);
    } finally {
      setLoading(false);
      setLoadingStatus('');
    }
  }, [asr]);

  // Transcribe a test file
  const transcribeFile = useCallback(async () => {
    setLoading(true);
    try {
      // In a real app, you'd get this from a file picker or recording
      const filePath = '/path/to/your/audio.wav';
      const transcription: ASRResult = await asr.transcribeFile(filePath);
      setResult(
        `Text: ${transcription.text}\n` +
          `Confidence: ${(transcription.confidence * 100).toFixed(1)}%\n` +
          `Speed: ${transcription.rtfx.toFixed(1)}x realtime`
      );
    } catch (error) {
      setResult(`Error: ${(error as Error).message}`);
    } finally {
      setLoading(false);
    }
  }, [asr]);

  // Initialize VAD
  const initializeVAD = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      await vad.initialize({ threshold: 0.85 });
      setResult('VAD initialized successfully');
    } catch (error) {
      setResult(`Error: ${(error as Error).message}`);
    } finally {
      setLoading(false);
    }
  }, [vad]);

  // Initialize Diarization
  const initializeDiarization = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      const initResult = await diarizer.initialize({
        clusteringThreshold: 0.7,
        numClusters: -1, // Auto-detect
      });
      setResult(`Diarization initialized in ${initResult.compilationDuration.toFixed(2)}s`);
    } catch (error) {
      setResult(`Error: ${(error as Error).message}`);
    } finally {
      setLoading(false);
      setLoadingStatus('');
    }
  }, [diarizer]);

  // Initialize TTS
  const initializeTTS = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      await tts.initialize({ variant: 'fiveSecond' });
      setResult('TTS initialized successfully');
    } catch (error) {
      setResult(`Error: ${(error as Error).message}`);
    } finally {
      setLoading(false);
      setLoadingStatus('');
    }
  }, [tts]);

  // Synthesize speech
  const synthesizeSpeech = useCallback(async () => {
    setLoading(true);
    try {
      const audio = await tts.synthesize('Hello from FluidAudio!');
      setResult(
        `Synthesized ${audio.duration.toFixed(2)}s of audio\n` +
          `Sample rate: ${audio.sampleRate}Hz`
      );
    } catch (error) {
      setResult(`Error: ${(error as Error).message}`);
    } finally {
      setLoading(false);
    }
  }, [tts]);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <Text style={styles.title}>FluidAudio Demo</Text>

        {/* System Info */}
        {systemInfo && (
          <View style={styles.infoBox}>
            <Text style={styles.infoTitle}>System Info</Text>
            <Text style={styles.infoText}>
              Platform: {systemInfo.platform}
              {'\n'}
              Apple Silicon: {systemInfo.isAppleSilicon ? 'Yes' : 'No'}
              {'\n'}
              {systemInfo.summary}
            </Text>
          </View>
        )}

        {/* Loading Status */}
        {loadingStatus ? (
          <View style={styles.statusBox}>
            <ActivityIndicator size="small" color="#007AFF" />
            <Text style={styles.statusText}>{loadingStatus}</Text>
          </View>
        ) : null}

        {/* ASR Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Speech-to-Text (ASR)</Text>
          <TouchableOpacity
            style={[styles.button, loading && styles.buttonDisabled]}
            onPress={initializeASR}
            disabled={loading}
          >
            <Text style={styles.buttonText}>Initialize ASR</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.button, loading && styles.buttonDisabled]}
            onPress={transcribeFile}
            disabled={loading}
          >
            <Text style={styles.buttonText}>Transcribe File</Text>
          </TouchableOpacity>
        </View>

        {/* VAD Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Voice Activity Detection</Text>
          <TouchableOpacity
            style={[styles.button, loading && styles.buttonDisabled]}
            onPress={initializeVAD}
            disabled={loading}
          >
            <Text style={styles.buttonText}>Initialize VAD</Text>
          </TouchableOpacity>
        </View>

        {/* Diarization Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Speaker Diarization</Text>
          <TouchableOpacity
            style={[styles.button, loading && styles.buttonDisabled]}
            onPress={initializeDiarization}
            disabled={loading}
          >
            <Text style={styles.buttonText}>Initialize Diarization</Text>
          </TouchableOpacity>
        </View>

        {/* TTS Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Text-to-Speech</Text>
          <TouchableOpacity
            style={[styles.button, loading && styles.buttonDisabled]}
            onPress={initializeTTS}
            disabled={loading}
          >
            <Text style={styles.buttonText}>Initialize TTS</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.button, loading && styles.buttonDisabled]}
            onPress={synthesizeSpeech}
            disabled={loading}
          >
            <Text style={styles.buttonText}>Synthesize Speech</Text>
          </TouchableOpacity>
        </View>

        {/* Result Display */}
        {result ? (
          <View style={styles.resultBox}>
            <Text style={styles.resultTitle}>Result</Text>
            <Text style={styles.resultText}>{result}</Text>
          </View>
        ) : null}

        {loading && !loadingStatus && (
          <ActivityIndicator size="large" color="#007AFF" style={styles.loader} />
        )}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContent: {
    padding: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 20,
    color: '#333',
  },
  infoBox: {
    backgroundColor: '#e3f2fd',
    padding: 15,
    borderRadius: 10,
    marginBottom: 20,
  },
  infoTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#1565c0',
  },
  infoText: {
    fontSize: 14,
    color: '#333',
    lineHeight: 20,
  },
  statusBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff3e0',
    padding: 12,
    borderRadius: 8,
    marginBottom: 15,
  },
  statusText: {
    marginLeft: 10,
    fontSize: 14,
    color: '#e65100',
  },
  section: {
    marginBottom: 20,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
    color: '#333',
  },
  button: {
    backgroundColor: '#007AFF',
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    marginBottom: 10,
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
    textAlign: 'center',
  },
  resultBox: {
    backgroundColor: '#e8f5e9',
    padding: 15,
    borderRadius: 10,
    marginTop: 10,
  },
  resultTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#2e7d32',
  },
  resultText: {
    fontSize: 14,
    color: '#333',
    lineHeight: 20,
  },
  loader: {
    marginTop: 20,
  },
});

export default App;
