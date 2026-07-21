from datetime import datetime, timedelta, timezone
from typing import Optional
from enum import Enum


class DutyStatus(str, Enum):
    OFF_DUTY = "off_duty"
    SLEEPER_BERTH = "sleeper_berth"
    DRIVING = "driving"
    ON_DUTY = "on_duty"


class HOSViolationType(str, Enum):
    DRIVING_LIMIT = "driving_limit"         # 11 hour driving limit
    DUTY_LIMIT = "duty_limit"               # 14 hour on-duty limit
    BREAK_REQUIRED = "break_required"       # 30 min break after 8h driving
    WEEKLY_LIMIT = "weekly_limit"           # 60/70 hour in 7/8 days
    RESTART_NEEDED = "restart_needed"       # Need 34h restart


# FMCSA HOS Regulations (Property-Carrying Drivers)
HOS_RULES = {
    "max_driving_hours": 11.0,          # 11 hours driving after 10h off
    "max_on_duty_hours": 14.0,          # 14 hours on-duty window
    "required_off_duty": 10.0,          # 10 hours off duty to reset
    "break_after_driving": 8.0,         # Must take break after 8h driving
    "required_break_minutes": 30,       # 30 minute break required
    "weekly_limit_7day": 60.0,          # 60h in 7 days
    "weekly_limit_8day": 70.0,          # 70h in 8 days
    "restart_hours": 34.0,             # 34h restart to reset weekly
}


class HOSService:
    """
    FMCSA-compliant Hours of Service calculator.
    Implements property-carrying driver rules (11h driving / 14h duty window).
    Reference: 49 CFR Part 395
    """

    def calculate_hos_summary(self, logs: list[dict]) -> dict:
        """
        Calculate complete HOS summary from log entries.
        Each log: {duty_status, start_time, end_time}
        """
        if not logs:
            return self._empty_summary()

        now = datetime.now(timezone.utc)

        # Sort by start time
        sorted_logs = sorted(logs, key=lambda x: x["start_time"])

        # Find last off-duty reset (10+ hours off duty)
        last_reset = self._find_last_reset(sorted_logs, now)

        # Calculate since last reset
        logs_since_reset = [
            log for log in sorted_logs
            if log["start_time"] >= last_reset
        ]

        # Driving time in current shift
        driving_hours = self._sum_driving_hours(logs_since_reset, now)

        # On-duty window start
        duty_window_start = self._find_duty_window_start(logs_since_reset)
        duty_window_hours = 0.0
        if duty_window_start:
            elapsed = (now - duty_window_start).total_seconds() / 3600
            duty_window_hours = min(elapsed, HOS_RULES["max_on_duty_hours"])

        # Hours remaining
        driving_remaining = max(0, HOS_RULES["max_driving_hours"] - driving_hours)
        duty_remaining = max(0, HOS_RULES["max_on_duty_hours"] - duty_window_hours)

        # The binding limit is the lesser of the two
        available_hours = min(driving_remaining, duty_remaining)

        # Break requirement
        continuous_driving = self._calc_continuous_driving(logs_since_reset, now)
        break_required = continuous_driving >= HOS_RULES["break_after_driving"]
        time_until_break = max(0, HOS_RULES["break_after_driving"] - continuous_driving)

        # 7-day / 8-day totals
        seven_day_hours = self._sum_on_duty_hours_in_window(sorted_logs, now, days=7)
        eight_day_hours = self._sum_on_duty_hours_in_window(sorted_logs, now, days=8)

        # Violations
        violations = self._check_violations(
            driving_hours, duty_window_hours, continuous_driving,
            seven_day_hours, eight_day_hours
        )

        # Current status
        current_log = sorted_logs[-1] if sorted_logs else None
        current_status = current_log["duty_status"] if current_log else "off_duty"

        # Time until reset (when driver can start fresh 10h off duty)
        time_to_reset = self._calculate_time_to_reset(logs_since_reset, now)

        return {
            "current_status": current_status,
            "driving_hours_used": round(driving_hours, 2),
            "driving_hours_remaining": round(driving_remaining, 2),
            "duty_window_hours_used": round(duty_window_hours, 2),
            "duty_window_hours_remaining": round(duty_remaining, 2),
            "available_drive_time_hours": round(available_hours, 2),
            "available_drive_time_formatted": self._format_hours(available_hours),
            "continuous_driving_hours": round(continuous_driving, 2),
            "break_required": break_required,
            "time_until_break_required_hours": round(time_until_break, 2),
            "seven_day_hours": round(seven_day_hours, 2),
            "seven_day_remaining": round(max(0, HOS_RULES["weekly_limit_7day"] - seven_day_hours), 2),
            "eight_day_hours": round(eight_day_hours, 2),
            "eight_day_remaining": round(max(0, HOS_RULES["weekly_limit_8day"] - eight_day_hours), 2),
            "last_reset_time": last_reset.isoformat() if last_reset else None,
            "hours_to_reset": round(time_to_reset, 2),
            "violations": violations,
            "cycle": "60h/7-day",  # or 70h/8-day based on driver preference
            "rules_version": "49 CFR Part 395",
        }

    def _find_last_reset(self, logs: list[dict], now: datetime) -> datetime:
        """Find the start of the current driving window (last 10+ hour off-duty period)."""
        # Work backward to find the last qualifying 10h off-duty
        for i in range(len(logs) - 1, 0, -1):
            log = logs[i]
            if log["duty_status"] in (DutyStatus.OFF_DUTY, DutyStatus.SLEEPER_BERTH):
                start = log["start_time"]
                end = log.get("end_time") or now
                duration_hours = (end - start).total_seconds() / 3600
                if duration_hours >= HOS_RULES["required_off_duty"]:
                    return end  # Reset happened at end of this off-duty period

        # If no reset found, go back 24 hours
        return now - timedelta(hours=24)

    def _sum_driving_hours(self, logs: list[dict], now: datetime) -> float:
        total = 0.0
        for log in logs:
            if log["duty_status"] == DutyStatus.DRIVING:
                end = log.get("end_time") or now
                duration = (end - log["start_time"]).total_seconds() / 3600
                total += duration
        return total

    def _sum_on_duty_hours_in_window(self, logs: list[dict], now: datetime, days: int) -> float:
        window_start = now - timedelta(days=days)
        total = 0.0
        for log in logs:
            if log["duty_status"] in (DutyStatus.DRIVING, DutyStatus.ON_DUTY):
                start = max(log["start_time"], window_start)
                end = min(log.get("end_time") or now, now)
                if end > start:
                    total += (end - start).total_seconds() / 3600
        return total

    def _find_duty_window_start(self, logs: list[dict]) -> Optional[datetime]:
        """Find start of current 14-hour duty window."""
        for log in logs:
            if log["duty_status"] in (DutyStatus.DRIVING, DutyStatus.ON_DUTY):
                return log["start_time"]
        return None

    def _calc_continuous_driving(self, logs: list[dict], now: datetime) -> float:
        """Calculate continuous driving since last qualifying break (30+ min off)."""
        total = 0.0
        # Work backward from most recent
        for log in reversed(logs):
            if log["duty_status"] == DutyStatus.DRIVING:
                end = log.get("end_time") or now
                total += (end - log["start_time"]).total_seconds() / 3600
            elif log["duty_status"] in (DutyStatus.OFF_DUTY, DutyStatus.SLEEPER_BERTH):
                end = log.get("end_time") or now
                duration_min = (end - log["start_time"]).total_seconds() / 60
                if duration_min >= HOS_RULES["required_break_minutes"]:
                    break  # Found qualifying break, stop accumulating
        return total

    def _calculate_time_to_reset(self, logs: list[dict], now: datetime) -> float:
        """Hours until 10h off-duty reset would complete."""
        # Find when the current off-duty period started
        last_log = logs[-1] if logs else None
        if last_log and last_log["duty_status"] in (DutyStatus.OFF_DUTY, DutyStatus.SLEEPER_BERTH):
            elapsed = (now - last_log["start_time"]).total_seconds() / 3600
            remaining = max(0, HOS_RULES["required_off_duty"] - elapsed)
            return remaining
        return HOS_RULES["required_off_duty"]

    def _check_violations(
        self, driving_h: float, duty_h: float, continuous_h: float,
        week7_h: float, week8_h: float
    ) -> list[dict]:
        violations = []

        if driving_h > HOS_RULES["max_driving_hours"]:
            violations.append({
                "type": HOSViolationType.DRIVING_LIMIT,
                "severity": "critical",
                "message": f"Exceeded 11-hour driving limit by {driving_h - HOS_RULES['max_driving_hours']:.1f}h",
            })
        elif driving_h > HOS_RULES["max_driving_hours"] - 1:
            violations.append({
                "type": HOSViolationType.DRIVING_LIMIT,
                "severity": "warning",
                "message": f"Less than 1 hour of drive time remaining",
            })

        if duty_h > HOS_RULES["max_on_duty_hours"]:
            violations.append({
                "type": HOSViolationType.DUTY_LIMIT,
                "severity": "critical",
                "message": f"Exceeded 14-hour duty window by {duty_h - HOS_RULES['max_on_duty_hours']:.1f}h",
            })

        if continuous_h >= HOS_RULES["break_after_driving"]:
            violations.append({
                "type": HOSViolationType.BREAK_REQUIRED,
                "severity": "critical",
                "message": "Mandatory 30-minute break required. Drove 8+ hours without break.",
            })

        if week7_h > HOS_RULES["weekly_limit_7day"]:
            violations.append({
                "type": HOSViolationType.WEEKLY_LIMIT,
                "severity": "critical",
                "message": f"Exceeded 60-hour/7-day limit by {week7_h - HOS_RULES['weekly_limit_7day']:.1f}h",
            })

        return violations

    def _empty_summary(self) -> dict:
        return {
            "current_status": "off_duty",
            "driving_hours_used": 0,
            "driving_hours_remaining": 11.0,
            "duty_window_hours_used": 0,
            "duty_window_hours_remaining": 14.0,
            "available_drive_time_hours": 11.0,
            "available_drive_time_formatted": "11h 0m",
            "continuous_driving_hours": 0,
            "break_required": False,
            "time_until_break_required_hours": 8.0,
            "seven_day_hours": 0,
            "seven_day_remaining": 60.0,
            "eight_day_hours": 0,
            "eight_day_remaining": 70.0,
            "last_reset_time": None,
            "hours_to_reset": 0,
            "violations": [],
            "cycle": "60h/7-day",
            "rules_version": "49 CFR Part 395",
        }

    def _format_hours(self, hours: float) -> str:
        h = int(hours)
        m = int((hours - h) * 60)
        return f"{h}h {m}m"


hos_service = HOSService()
