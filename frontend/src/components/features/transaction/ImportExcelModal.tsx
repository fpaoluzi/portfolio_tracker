'use client';

import { useState, FormEvent, ChangeEvent } from 'react';
import { Upload, FileSpreadsheet, CheckCircle, AlertCircle } from 'lucide-react';
import { Modal, Button } from '@/components/ui';

interface ImportExcelModalProps {
  portfolioId: string;
  onClose: () => void;
  onSuccess: () => void;
}

interface ImportResult {
  success: boolean;
  message: string;
  results?: {
    imported: number;
    skipped: number;
    newAssets: number;
    errors: Array<{ row: string; error: string }>;
  };
}

export const ImportExcelModal: React.FC<ImportExcelModalProps> = ({
  portfolioId,
  onClose,
  onSuccess,
}) => {
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);

  const handleFileChange = (e: ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      setFile(e.target.files[0]);
      setResult(null);
    }
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();

    if (!file) {
      alert('Seleziona un file Excel');
      return;
    }

    setUploading(true);

    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('portfolioId', portfolioId.toString());

      const response = await fetch('http://localhost:3001/api/import/excel', {
        method: 'POST',
        body: formData,
      });

      const data = await response.json();

      if (response.ok) {
        setResult(data);
        if (data.success) {
          setTimeout(() => {
            onSuccess();
            onClose();
          }, 3000);
        }
      } else {
        setResult({
          success: false,
          message: data.error || 'Errore durante l\'import',
        });
      }
    } catch (error) {
      console.error('Error uploading file:', error);
      setResult({
        success: false,
        message: 'Errore di connessione al server',
      });
    } finally {
      setUploading(false);
    }
  };

  return (
    <Modal title="Importa Transazioni da Excel" onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* File Upload */}
        <div>
          <label className="block text-sm font-medium text-blue-200 mb-2">
            Seleziona file Excel (.xlsx)
          </label>
          <div className="relative">
            <input
              type="file"
              accept=".xlsx,.xls"
              onChange={handleFileChange}
              className="hidden"
              id="excel-upload"
            />
            <label
              htmlFor="excel-upload"
              className="flex flex-col items-center justify-center w-full h-32 border-2 border-dashed border-white/30 rounded-lg cursor-pointer hover:border-blue-400 hover:bg-white/5 transition-all"
            >
              {file ? (
                <div className="flex items-center gap-3">
                  <FileSpreadsheet className="w-8 h-8 text-green-400" />
                  <div>
                    <div className="text-white font-medium">{file.name}</div>
                    <div className="text-xs text-blue-300">
                      {(file.size / 1024).toFixed(2)} KB
                    </div>
                  </div>
                </div>
              ) : (
                <>
                  <Upload className="w-12 h-12 text-blue-400 mb-2" />
                  <span className="text-white">
                    Clicca per selezionare un file
                  </span>
                  <span className="text-xs text-blue-300 mt-1">
                    Excel (.xlsx, .xls)
                  </span>
                </>
              )}
            </label>
          </div>
        </div>

        {/* Istruzioni */}
        <div className="bg-blue-500/10 border border-blue-400/30 rounded-lg p-4">
          <h4 className="text-sm font-medium text-blue-200 mb-2">
            Formato file richiesto:
          </h4>
          <ul className="text-xs text-blue-300 space-y-1">
            <li>• Colonne: Titolo, ISIN, Quantità, Prezzo, Data, Commissioni</li>
            <li>• Solo "Compravendita titoli" sarà importata</li>
            <li>• Gli asset mancanti saranno creati automaticamente</li>
            <li>• Le commissioni vengono sommate automaticamente</li>
          </ul>
        </div>

        {/* Result */}
        {result && (
          <div
            className={`border rounded-lg p-4 ${
              result.success
                ? 'bg-green-500/10 border-green-400/30'
                : 'bg-red-500/10 border-red-400/30'
            }`}
          >
            <div className="flex items-start gap-3">
              {result.success ? (
                <CheckCircle className="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" />
              ) : (
                <AlertCircle className="w-6 h-6 text-red-400 flex-shrink-0 mt-0.5" />
              )}
              <div className="flex-1">
                <div
                  className={`font-medium ${
                    result.success ? 'text-green-200' : 'text-red-200'
                  }`}
                >
                  {result.message}
                </div>
                {result.results && (
                  <div className="mt-2 text-sm space-y-1">
                    <div className="text-white">
                      ✓ Transazioni importate: {result.results.imported}
                    </div>
                    <div className="text-white">
                      ✓ Nuovi asset creati: {result.results.newAssets}
                    </div>
                    <div className="text-blue-300">
                      ⊘ Righe saltate: {result.results.skipped}
                    </div>
                    {result.results.errors.length > 0 && (
                      <div className="mt-2">
                        <div className="text-red-300 font-medium">Errori:</div>
                        {result.results.errors.slice(0, 3).map((err, i) => (
                          <div key={i} className="text-xs text-red-200 ml-2">
                            • {err.row}: {err.error}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-3 justify-end pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Annulla
          </Button>
          <Button
            type="submit"
            variant="primary"
            icon={Upload}
            disabled={!file || uploading}
          >
            {uploading ? 'Importando...' : 'Importa Transazioni'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
