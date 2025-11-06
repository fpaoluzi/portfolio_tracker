'use client';

import { ButtonHTMLAttributes } from 'react';
import { LucideIcon } from 'lucide-react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'success' | 'danger' | 'warning' | 'purple';
  icon?: LucideIcon;
  children: React.ReactNode;
}

const variantClasses = {
  primary: 'bg-blue-500 hover:bg-blue-600',
  secondary: 'bg-white/10 hover:bg-white/20',
  success: 'bg-green-500 hover:bg-green-600',
  danger: 'bg-red-500 hover:bg-red-600',
  warning: 'bg-orange-500 hover:bg-orange-600',
  purple: 'bg-purple-500 hover:bg-purple-600',
};

export const Button: React.FC<ButtonProps> = ({
  variant = 'primary',
  icon: Icon,
  children,
  className = '',
  ...props
}) => {
  return (
    <button
      className={`px-4 py-2 text-white rounded-lg flex items-center gap-2 transition-all disabled:opacity-50 disabled:cursor-not-allowed ${variantClasses[variant]} ${className}`}
      {...props}
    >
      {Icon && <Icon className="w-4 h-4" />}
      {children}
    </button>
  );
};
