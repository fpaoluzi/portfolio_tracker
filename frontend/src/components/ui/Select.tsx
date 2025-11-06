'use client';

import { SelectHTMLAttributes } from 'react';

interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  children: React.ReactNode;
}

export const Select: React.FC<SelectProps> = ({ label, className = '', children, ...props }) => {
  return (
    <div>
      {label && (
        <label className="block text-sm font-medium text-blue-200 mb-2">{label}</label>
      )}
      <select
        className={`w-full px-4 py-2 bg-slate-700/50 border border-white/20 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent appearance-none cursor-pointer ${className}`}
        style={{
          backgroundImage: `url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 20 20'%3e%3cpath stroke='%23fff' stroke-linecap='round' stroke-linejoin='round' stroke-width='1.5' d='M6 8l4 4 4-4'/%3e%3c/svg%3e")`,
          backgroundPosition: 'right 0.5rem center',
          backgroundRepeat: 'no-repeat',
          backgroundSize: '1.5em 1.5em',
          paddingRight: '2.5rem'
        }}
        {...props}
      >
        {children}
      </select>
    </div>
  );
};
