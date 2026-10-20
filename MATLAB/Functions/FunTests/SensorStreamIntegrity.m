classdef SensorStreamIntegrity
    % Pure helpers shared by the live monitor and acquisition regression tests.
    methods (Static)
        function [lines, pending] = decodeChunk(pending, chunk)
            bytes = [reshape(uint8(pending), 1, []), reshape(uint8(chunk), 1, [])];
            ends = find(bytes == 10);
            lines = cell(numel(ends), 1);
            first = 1;
            for k = 1:numel(ends)
                last = ends(k) - 1;
                if last >= first && bytes(last) == 13
                    last = last - 1;
                end
                lines{k} = char(bytes(first:last));
                first = ends(k) + 1;
            end
            pending = bytes(first:end);
            if numel(pending) > 4096
                error('SensorStreamIntegrity:UnterminatedLine', ...
                    'More than 4096 serial bytes without LF. Check matching baud settings.');
            end
        end

        function [values, kind] = parseSample(line)
            values = [];
            kind = "corrupt";
            text = char(line);
            if any(double(text) < 32 | double(text) > 126)
                return;
            end
            number = '(-?\d+\.\d{4}|nan)';
            pattern = ['^(\d+);' number ',' number ',' number ',' number '$'];
            tokens = regexp(text, pattern, 'tokens', 'once');
            if isempty(tokens)
                return;
            end
            values = str2double(tokens);
            if ~isfinite(values(1)) || values(1) > flintmax
                values = [];
                return;
            end
            if all(isnan(values(2:5)))
                kind = "fault";
                return;
            end
            if any(~isfinite(values)) || any(abs(values(2:4)) > 16) || ...
                    values(5) < 0 || abs(norm(values(2:4)) - values(5)) > 0.00025
                values = [];
                return;
            end
            kind = "sample";
        end

        function [t, y, status] = fftWindow(t, y, seconds, rate, minSamples)
            status = "";
            if isempty(t)
                status = "Waiting for data";
                return;
            end
            keep = t >= max(0, t(end) - seconds);
            t = t(keep);
            y = y(keep);
            if numel(t) < minSamples
                status = sprintf('Waiting for at least %d samples', minSamples);
            elseif any(~isfinite(t) | ~isfinite(y))
                status = "FFT withheld: invalid data or a stream break in the window";
            elseif any(abs(diff(t) - 1/rate) > 0.25/rate)
                status = "FFT withheld: missing, duplicate, or out-of-order samples";
            end
            % Do not sort, deduplicate, fill missing samples, or interpolate.
        end

        function [tPlot, yPlot] = breakPlot(t, y, rate)
            t = t(:); y = y(:);
            if isempty(t)
                tPlot = t; yPlot = y;
                return;
            end
            breakBefore = [false; diff(t) <= 0 | diff(t) > 1.5/rate];
            destinations = (1:numel(t)).' + cumsum(breakBefore);
            tPlot = zeros(numel(t) + nnz(breakBefore), 1);
            yPlot = nan(size(tPlot));
            tPlot(destinations) = t;
            yPlot(destinations) = y;
            tPlot(destinations(breakBefore) - 1) = t(breakBefore);
        end
    end
end
