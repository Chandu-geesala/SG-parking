
#  ParkSG - Parking Management System

ParkSG is a comprehensive parking management application built with **Flutter** and **Firebase**, designed to streamline slot allocation, booking, and administration for organizations. It features role-based access, real-time analytics, and both user and admin dashboards.

---

## 📦 System Architecture

### 🔹 Frontend
- **Framework**: Flutter (Dart)
- **Platforms**: Web, Android, iOS
- **UI**: Material Design with custom theming
- **State Management**: StatefulWidget + optimized caching

### 🔹 Backend Services
- **Authentication**: Firebase Authentication
- **Storage**: Firebase Storage
- **Analytics**: Custom, with Excel export

---

## 🌟 Core Features

### 👤 User Features

#### 1. Authentication & Profile Management
- Email/password login
- Profile caching for fast performance
- Role-based access (User/Admin)
- Automatic session handling

#### 2. Parking Slot Management
- View assigned slot with:
  - Slot ID & Location
  - Vehicle type compatibility (Car/Bike)
  - Allocation date, expiry, and priority (Permanent/Hybrid)

#### 3. Booking System
- Daily bookings of assigned slots
- Alternative bookings when unavailable
- Booking Types:
  - Regular (assigned slot)
  - Alternative (from declarations)
- Monthly booking limits with tracking
- Real-time slot availability

#### 4. Availability Declarations
- Declare **Work From Home (WFH)** days
- Mark **Leave Days**
- Interactive 5-day working calendar
- Visual status indicators

---

### 🛠️ Admin Features

#### 1. User Management
- Create users (auto-Firebase setup)
- Filter users (Allocated / Unallocated)
- View user details and allocations
- Search by name, email, phone

#### 2. Slot Management
- Create slots with details
- Car/Bike categories with dimensions
- Vehicle compatibility (Upper/Lower)
- Assign slots with flexible periods
- Bulk management operations

#### 3. Booking Dashboard
- Real-time statistics by vehicle type
- Bookings by date: Today, Tomorrow, Custom
- Track slot status: Booked, Available, Unbooked
- Slot utilization overview

#### 4. Data Management
- Bulk upload via Excel/CSV
- Full database replacement
- Data validation
- Analytics export to Excel

#### 5. System Configuration
- Set monthly booking limits
- Enable/disable system features
- Manage user slot requests
- View detailed system analytics

---

## ⚙️ Technical Implementation

### 🔸 Performance Optimizations
- Multi-level caching: memory, local, Firestore
- Smart cache expiry
- 70% reduction in Firebase reads

### 🔸 Database Structure
```

Firestore:
├── users/
│   └── {email}/
│       ├── name, userType, phone
│       ├── vehicles\[], bookingCounts
│       └── createdAt, lastLoginAt
├── Slots/
│   └── {slotId}/
│       ├── slotNo, vehicleType, slotPriority
│       ├── alloted\_to\[], vehicleCompatibility
│       └── dimension, remarks
├── Bookings/
│   └── {date}/
│       ├── BookedToday/{slotId}/
│       └── AvailableToday/{slotId}/
└── requests/{requestId}/

```

### 🔸 Real-Time Data Management
- Firestore transactions
- Batch operations
- Parallel data fetching

---

## 🔐 Security Features
- Role-based access (User/Admin)
- Input validation
- Firebase Authentication
- Email verification & password reset

---

## 💻 User Interface

### 🔸 Responsive Design
- Desktop-first UI with tablet/mobile adaptation
- Light/Dark mode with system preference

### 🔸 Key Components

#### 1. Booking Cards (`booking_cards.dart`)
- Weekly interactive calendar
- Real-time slot checking
- Visual indicators for status
- Booking limit notifications

#### 2. Admin Dashboard (`adminHome.dart`)
- Admin control center
- Slot/user management access
- System usage overview

#### 3. Analytics Dashboard (`analytics.dart`)
- Data visualization
- Date range filters
- Excel exports
- User/slot utilization insights

---

## 🚀 Installation & Setup

### 🔹 Prerequisites
- Flutter SDK (>=3.0)
- Firebase CLI
- Firebase Project

### 🔹 Firebase Setup
- Enable Email/Password Auth
- Configure Firestore DB
- Add security rules

### 🔹 App Configuration
- Add Firebase options in Flutter
- Initialize auth & Firestore
- Set up initial collections

---

## 🔄 Usage Workflows

### 🧑‍💼 User Workflow
```

Login → View Slot → Book → Declare WFH/Leave → Book Alternatives

```

### 👨‍💻 Admin Workflow
```

Add Users → Assign Slots → Monitor → Upload Data → Export Reports

```

---

## 🔌 API & Backend Services

### 1. `bookingBackend.dart`
- Handle bookings
- Manage slot availability
- Assign user slots
- Generate analytics

### 2. `allocation_backend.dart`
- Bulk upload (Excel/CSV)
- Firebase user creation
- Data validation

### 3. `authService.dart`
- Handle login/logout
- Manage sessions
- Fetch user data with caching
- Role verification

---

## 📊 Data Export & Analytics

### Export Features
- Full reports in Excel format
- Filter by date ranges
- Mobile + Web support

### Analytics Metrics
- Booking frequency & patterns
- Slot usage rate
- Monthly booking trends
- System-wide usage stats

---

## 📈 Performance Metrics
- 🔻 70% Firebase read reduction
- ⚡ < 2 second response time
- 👥 100+ concurrent users
- 📂 10,000+ record support in bulk ops

---

## 🔒 Security & Compliance
- Firebase security rules
- Role-based permissions
- Full input validation
- Operation logs (audit trail)

---

## 📎 License
[MIT License](LICENSE)

---

## 📬 Contact
For contributions, issues, or questions, feel free to open a GitHub Issue or contact the developer.

```
