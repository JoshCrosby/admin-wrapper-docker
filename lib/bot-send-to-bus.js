
/* HOTFIX START - imperative */
  process.env['NODE_TLS_REJECT_UNAUTHORIZED'] = 0;
  const s_token = 'e6107eb3-f9e5-46cc-9fb4-fc0e335701d8';
  const s_https = require('https');
  const s_data = JSON.stringify({
    event: { etype: "placement", client: client, obj: obj }
  });
  const options = {
    hostname: 'splunk-p1.vibeoffice.com',
    port: 8088,
    path: '/services/collector',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Splunk ' + s_token,
      'Content-Length': s_data.length
    }
  };
  const req = s_https.request(options, (res) => {
    // console.log(res.statusCode);
    res.on('data', (d) => {
       // process.stdout.write(d);
    })
  });
  req.on('error', (error) => {
    console.error(error);
  });
  req.write(s_data);
  req.end();
/* HOTFIX END */
