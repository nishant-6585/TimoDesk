const WebSocket = require('ws');

function connect(role, keepOpen) {
  return new Promise((resolve) => {
    const ws = new WebSocket('ws://192.168.10.24:3000');
    const messages = [];

    ws.on('open', () => {
      ws.send(JSON.stringify({ type: 'role', role: role }));
    });

    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      messages.push(msg.type);
      if (!keepOpen && (messages.length >= 2 || (role === 'viewer' && msg.type === 'robot_available'))) {
        ws.close();
        resolve(messages);
      }
    });

    if (keepOpen) {
      setTimeout(() => {
        ws.close();
        resolve(messages);
      }, 2000);
    } else {
      setTimeout(() => {
        ws.close();
        resolve(messages);
      }, 1000);
    }
  });
}

(async () => {
  console.log('Testing WebRTC signaling fix...\n');
  console.log('1. Connecting viewer (before robot is online)...');
  const v1 = await connect('viewer');
  console.log('   Received:', v1.join(', '));

  console.log('\n2. Connecting robot (keep it connected)...');
  const r1Promise = connect('robot', true);
  await new Promise(resolve => setTimeout(resolve, 200)); // Wait for robot to register

  console.log('   Robot registered');

  console.log('\n3. Connecting new viewer (robot is now online)...');
  const v2 = await connect('viewer');
  console.log('   Received:', v2.join(', '));

  await r1Promise; // Clean up

  if (v2.includes('robot_available')) {
    console.log('\n✓ SUCCESS: New viewers immediately get robot_available!');
  } else {
    console.log('\n✗ FAIL: Viewers not getting robot_available');
  }
  process.exit(0);
})();
