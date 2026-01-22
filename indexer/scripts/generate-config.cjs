const fs = require('fs');
const path = require('path');

const templatePath = path.join(__dirname, '../config.template.yaml');
const configPath = path.join(__dirname, '../config.yaml');

// Default address from original config
const DEFAULT_ADDRESS = "0x212f275c6dd4829cd84abdf767b0df4a9cb9ef60";
const address = process.env.PROTOCOL_ADAPTER_ADDRESS || DEFAULT_ADDRESS;

try {
  let template = fs.readFileSync(templatePath, 'utf8');
  const config = template.replace(/{{PROTOCOL_ADAPTER_ADDRESS}}/g, address);
  
  fs.writeFileSync(configPath, config);
  console.log(`Generated config.yaml with ProtocolAdapter address: ${address}`);
} catch (error) {
  console.error("Error generating config:", error);
  process.exit(1);
}
