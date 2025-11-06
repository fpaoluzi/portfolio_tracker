'use client';

import { TextareaHTMLAttributes } from 'react';

interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
}

export const Textarea: React.FC<TextareaProps> = ({ label, className = '', ...props }) => {
  return (
    <div>
      {label && (
        <label className="block text-sm font-medium text-blue-200 mb-2">{label}</label>
      )}
      <textarea
        className={`w-full px-4 py-2 bg-slate-700/50 border border-white/20 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent ${className}`}
        {...props}
      />
    </div>
  );
};
