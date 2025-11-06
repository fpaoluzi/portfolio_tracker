'use client';

import { InputHTMLAttributes } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
}

export const Input: React.FC<InputProps> = ({ label, className = '', ...props }) => {
  return (
    <div>
      {label && (
        <label className="block text-sm font-medium text-blue-200 mb-2">{label}</label>
      )}
      <input
        className={`w-full px-4 py-2 bg-slate-700/50 border border-white/20 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent ${className}`}
        {...props}
      />
    </div>
  );
};
