import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { DEFAULT_SETTINGS, type SettingsPatch } from '@madi/shared';
import { api, queryKeys } from './api.js';

export function useSettings() {
  const q = useQuery({ queryKey: queryKeys.settings, queryFn: api.settings });
  return { ...q, settings: q.data?.settings ?? DEFAULT_SETTINGS };
}

/** 설정 저장. 성공하면 캐시를 바로 갱신하고 폴더 후보 목록도 다시 읽는다. */
export function usePatchSettings() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (patch: SettingsPatch) => api.patchSettings(patch),
    onSuccess: (data) => {
      qc.setQueryData(queryKeys.settings, data);
      void qc.invalidateQueries({ queryKey: queryKeys.folders });
      void qc.invalidateQueries({ queryKey: queryKeys.health });
      void qc.invalidateQueries({ queryKey: queryKeys.videos });
    },
  });
}
