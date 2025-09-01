import { Text } from 'react-native';
import { colors } from '~/theme/colors';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
export default function MgActiveBadge(){
  const { mgActiveNow } = useAlertnessSeries();
  return <Text style={{ color: colors.textSecondary }}>Active caffeine: {Math.round(mgActiveNow)} mg</Text>;
}
  