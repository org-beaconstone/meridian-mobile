import React from 'react';
import ReactDOM from 'react-dom/client';
import '@atlaskit/css-reset';
import '@fontsource/dm-sans';
import '@fontsource/manrope';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
